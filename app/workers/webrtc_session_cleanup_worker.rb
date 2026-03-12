class WebrtcSessionCleanupWorker
  include Sidekiq::Worker

  sidekiq_options queue: :critical, retry: false

  def perform
    active_pairs.each do |app_id, room_name|
      evict_stale_participants(app_id, room_name)
    end
  end

  private

  def active_pairs
    Room
      .active
      .joins(application: :api_credentials)
      .where(api_credentials: { active: true })
      .distinct
      .pluck("api_credentials.app_id", "rooms.display_name")
  end

  def evict_stale_participants(app_id, room_name)
    rm = WebrtcRoomManager.new(app_id: app_id)
    participants = rm.get_participants(room_name)
    return if participants.empty?

    participants.each_value do |participant|
      pid = participant["participant_id"]
      next if pid.blank? || rm.heartbeat_active?(pid)

      remaining = rm.leave_room(room_name, participant_id: pid)
      next unless remaining

      if remaining.zero?
        Room.find_active_for(app_id: app_id, name: room_name)&.end_room!
        log_room_ended(app_id, room_name)
        dispatch_webhook(app_id, "room.ended", room_name, ended_at: Time.current.iso8601)
      end

      ActionCable.server.broadcast(
        "webrtc:#{app_id}:#{room_name}:signals",
        {
          type:                   "participant_left",
          participant_id:         pid,
          remaining_participants: remaining,
          evicted:                true,
          timestamp:              Time.current.iso8601
        }
      )

      dispatch_webhook(app_id, "participant.left", room_name,
                       participant_id: pid, reason: "evicted")
      close_cf_session_async(participant["session_id"])
    end
  end

  def log_room_ended(app_id, room_name)
    application_id = ApiCredential.active.find_by(app_id: app_id)&.application_id
    return unless application_id

    CallEventLogger.log(
      application_id: application_id,
      event_type: "room.ended",
      room_name: room_name
    )
  rescue StandardError => e
    Rails.logger.error("[WebrtcSessionCleanupWorker] room.ended log failed: #{e.message}")
  end

  def dispatch_webhook(app_id, event_type, room_name, payload = {})
    application = ApiCredential.active.find_by(app_id: app_id)&.application
    return unless application

    WebhookDispatchService.dispatch(
      application: application,
      event_type: event_type,
      payload: payload.merge(room_id: room_name, application_id: application.id)
    )
  rescue StandardError => e
    Rails.logger.error("[WebrtcSessionCleanupWorker] webhook dispatch failed: #{e.message}")
  end

  def close_cf_session_async(session_id)
    return if session_id.blank?

    Cloudflare::Calls.new.close_tracks(session_id, track_mids: [ "*" ], force: true)
  rescue Cloudflare::HttpClient::ApiError => e
    Rails.logger.warn("[WebrtcSessionCleanupWorker] CF session close failed " \
                      "for session #{session_id}: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[WebrtcSessionCleanupWorker] Unexpected error closing CF session " \
                       "#{session_id}: #{e.message}")
  end
end
