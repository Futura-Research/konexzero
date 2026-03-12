class WebrtcAnalyticsWorker
  include Sidekiq::Worker

  sidekiq_options queue: :low, retry: 3

  # Performs an async DB write for a WebRTC call event.
  # Never raises — analytics must never disrupt the signaling hot path.
  #
  # @param application_id [String] UUID of the tenant application
  # @param event_type [String] one of WebrtcCallEvent::VALID_EVENT_TYPES
  # @param room_name [String] raw room name
  # @param participant_id [String, nil]
  # @param payload [Hash]
  def perform(application_id, event_type, room_name, participant_id, payload)
    WebrtcCallEvent.create!(
      application_id: application_id,
      event_type: event_type,
      room_name: room_name,
      participant_id: participant_id.presence,
      payload: payload || {},
      occurred_at: Time.current
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[WebrtcAnalyticsWorker] Skipping invalid event " \
                      "(#{event_type}): #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[WebrtcAnalyticsWorker] Unexpected error writing call event " \
                       "(#{event_type}): #{e.message}")
  end
end
