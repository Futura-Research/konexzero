class RoomChannel < ApplicationCable::Channel
  # Authenticates the subscriber and starts streaming room signals.
  #
  # Rejects when:
  #   - room_id param doesn't match the JWT claim (prevents subscription spoofing)
  #   - Participant is not present in Redis (must call REST /join first)
  def subscribed
    return reject if params[:room_id] != room_id
    return reject unless room_manager.get_participant(room_id, participant_id)

    stream_from room_stream
    room_manager.set_heartbeat(participant_id)
  end

  # Cleans up Redis state and broadcasts participant_left.
  # Guard against nil identifiers covers the rejected-connection cleanup path
  # (AnyCable calls unsubscribed even for rejected subscriptions).
  def unsubscribed
    return unless app_id && room_id && participant_id

    room_manager.del_heartbeat(participant_id)

    remaining = room_manager.leave_room(room_id, participant_id: participant_id)
    # nil means the participant was already removed (e.g. via REST /leave).
    # Skip cleanup and broadcast — a duplicate participant_left was already sent.
    return unless remaining

    if remaining.zero?
      Room.find_active_for(app_id: app_id, name: room_id)&.end_room!
      channel_log_event("room.ended")
      channel_dispatch_webhook("room.ended", ended_at: Time.current.iso8601)
    end

    ActionCable.server.broadcast(room_stream, participant_left_payload(remaining))

    channel_log_event("participant.left")
    channel_dispatch_webhook("participant.left", participant_id: participant_id, reason: "disconnected")
  end

  # Public action: client sends { "action": "heartbeat" }
  # Refreshes the presence TTL — no broadcast, silent acknowledgement.
  def heartbeat(_data = {})
    room_manager.set_heartbeat(participant_id)
  end

  # Public action: client sends { "action": "media_state_changed", ... }
  # ActionCable dispatches to this method directly.
  # Validates at least one boolean field is present before updating Redis or broadcasting.
  def media_state_changed(data)
    audio_muted = data["audio_muted"]
    video_muted = data["video_muted"]

    return unless [ audio_muted, video_muted ].any? { |v| v == true || v == false }

    # update_media_state returns nil when the participant is not in Redis
    # (e.g. removed by a cleanup job between subscribe and receive).
    # Skip the broadcast to avoid advertising state for a departed participant.
    return unless room_manager.update_media_state(room_id, participant_id,
                                                  audio_muted: audio_muted,
                                                  video_muted: video_muted)

    ActionCable.server.broadcast(room_stream, {
      type:           "media_state_changed",
      participant_id: participant_id,
      audio_muted:    audio_muted,
      video_muted:    video_muted,
      timestamp:      Time.current.iso8601
    })
  end

  # Public action: client sends { "action": "force_mute", "target_participant_id": "..." }
  # Advisory — no server-side state mutation; the target client decides to mute locally.
  def force_mute(data)
    target = data["target_participant_id"]
    return if target.blank?

    ActionCable.server.broadcast(room_stream, {
      type:                     "force_mute",
      target_participant_id:    target,
      requester_participant_id: participant_id,
      timestamp:                Time.current.iso8601
    })
  end

  private

  # Logs a call event using connection identifiers (no current_application available here).
  # Wrapped in rescue — analytics must never disrupt the WebSocket disconnect path.
  def channel_log_event(event_type, payload: {})
    CallEventLogger.log(
      application_id: app_id_to_application_id,
      event_type:,
      room_name: room_id,
      participant_id: participant_id,
      payload:
    )
  rescue StandardError => e
    Rails.logger.error("[RoomChannel#channel_log_event] #{e.message}")
  end

  # Resolves the DB application UUID from the app_id credential identifier.
  # Returns nil if credential is not found — analytics will be skipped gracefully.
  def app_id_to_application_id
    @app_id_to_application_id ||=
      ApiCredential.active.find_by(app_id: app_id)&.application_id
  end

  def room_manager
    @room_manager ||= WebrtcRoomManager.new(app_id: app_id)
  end

  # Dispatches a webhook via the application resolved from app_id.
  # Wrapped in rescue — webhooks must never disrupt the WebSocket disconnect path.
  def channel_dispatch_webhook(event_type, payload = {})
    application = ApiCredential.active.find_by(app_id: app_id)&.application
    return unless application

    WebhookDispatchService.dispatch(
      application: application,
      event_type: event_type,
      payload: payload.merge(room_id: room_id, application_id: application.id)
    )
  rescue StandardError => e
    Rails.logger.error("[RoomChannel#channel_dispatch_webhook] #{e.message}")
  end

  def room_stream
    @room_stream ||= "webrtc:#{app_id}:#{room_id}:signals"
  end

  def participant_left_payload(remaining)
    {
      type:                   "participant_left",
      participant_id:         participant_id,
      remaining_participants: remaining,
      timestamp:              Time.current.iso8601
    }
  end
end
