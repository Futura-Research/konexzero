class MessagePersistenceWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 3

  def perform(app_id, room_name, attrs)
    application_id = ApiCredential.active.find_by(app_id: app_id)&.application_id
    return unless application_id

    Message.create!(
      id:                attrs["id"],
      application_id:    application_id,
      room_name:         room_name,
      sender_id:         attrs["sender_id"],
      recipient_id:      attrs["recipient_id"],
      message_type:      attrs["message_type"],
      content:           attrs["content"],
      payload:           attrs["payload"] || {},
      client_message_id: attrs["client_message_id"],
      sent_at:           attrs["sent_at"] || Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[MessagePersistenceWorker] Duplicate message skipped " \
                      "(client_message_id: #{attrs['client_message_id']})")
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[MessagePersistenceWorker] Invalid message skipped: #{e.message}")
  end
end
