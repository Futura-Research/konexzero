class MessageChannel < ApplicationCable::Channel
  # Reuses the WebRTC JWT connection (app_id, room_id, participant_id identifiers).
  # The subscriber must have already called REST /join before subscribing here.
  def subscribed
    unless room_manager.get_participant(room_id, participant_id)
      return reject
    end

    stream_from room_stream
    stream_from dm_stream
  end

  # No-op: messaging is stateless at the channel level.
  def unsubscribed; end

  # Client action: { "action": "send_message", "message_type": "text", "content": "...", ... }
  #
  # Validates input, broadcasts immediately (before DB write), then enqueues
  # MessagePersistenceWorker for async persistence.
  def send_message(data)
    message_type       = data["message_type"]
    content            = data["content"]
    payload            = data["payload"] || {}
    recipient_id       = data["recipient_id"].presence
    client_message_id  = data["client_message_id"].presence

    return unless valid_message_type_for_client?(message_type)
    return unless content_valid?(message_type, content)
    return unless payload_valid?(message_type, payload)
    return if duplicate_message?(client_message_id)

    message_id = SecureRandom.uuid
    sent_at    = Time.current.iso8601

    broadcast_payload = {
      type:              "message",
      message_id:        message_id,
      sender_id:         participant_id,
      message_type:      message_type,
      content:           content,
      payload:           payload.presence,
      recipient_id:      recipient_id,
      client_message_id: client_message_id,
      sent_at:           sent_at
    }

    target_stream = recipient_id ? "msg:#{app_id}:#{room_id}:dm:#{recipient_id}" : room_stream
    ActionCable.server.broadcast(target_stream, broadcast_payload)

    MessagePersistenceWorker.perform_async(
      app_id,
      room_id,
      {
        "id"                => message_id,
        "sender_id"         => participant_id,
        "recipient_id"      => recipient_id,
        "message_type"      => message_type,
        "content"           => content,
        "payload"           => payload,
        "client_message_id" => client_message_id,
        "sent_at"           => sent_at
      }
    )
  end

  # Client action: { "action": "typing_started" }
  # Ephemeral — broadcasts to room only; no DB write.
  def typing_started(_data = {})
    ActionCable.server.broadcast(room_stream, {
      type:           "typing_started",
      participant_id: participant_id,
      timestamp:      Time.current.iso8601
    })
  end

  # Client action: { "action": "typing_stopped" }
  # Ephemeral — broadcasts to room only; no DB write.
  def typing_stopped(_data = {})
    ActionCable.server.broadcast(room_stream, {
      type:           "typing_stopped",
      participant_id: participant_id,
      timestamp:      Time.current.iso8601
    })
  end

  private

  def room_manager
    @room_manager ||= WebrtcRoomManager.new(app_id: app_id)
  end

  def room_stream
    @room_stream ||= "msg:#{app_id}:#{room_id}:room"
  end

  def dm_stream
    @dm_stream ||= "msg:#{app_id}:#{room_id}:dm:#{participant_id}"
  end

  # Clients may only send text or custom_data — system messages are server-initiated only.
  def valid_message_type_for_client?(message_type)
    %w[text custom_data].include?(message_type)
  end

  def content_valid?(message_type, content)
    return content.present? if message_type == "text"

    true
  end

  def payload_valid?(message_type, payload)
    return payload.present? if message_type == "custom_data"

    true
  end

  # Idempotency guard: check DB for an already-persisted message with this client_message_id.
  # Returns true (skip) if a duplicate is found, false otherwise.
  # Uses application_id (UUID) rather than the association name to avoid ambiguity.
  def duplicate_message?(client_message_id)
    return false unless client_message_id

    app_uuid = app_id_to_application_id
    return false unless app_uuid

    Message.exists?(
      application_id: app_uuid,
      client_message_id: client_message_id
    )
  end

  # Resolves the DB application UUID from the app_id credential identifier.
  def app_id_to_application_id
    @app_id_to_application_id ||=
      ApiCredential.active.find_by(app_id: app_id)&.application_id
  end
end
