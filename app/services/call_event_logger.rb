class CallEventLogger
  # Enqueues an async analytics write. Never blocks the signaling hot path.
  #
  # @param application_id [String, UUID] tenant application ID
  # @param event_type [String] one of WebrtcCallEvent::VALID_EVENT_TYPES
  # @param room_name [String] raw room name (not namespaced)
  # @param participant_id [String, nil] nil for room-level events
  # @param payload [Hash] arbitrary structured metadata
  def self.log(application_id:, event_type:, room_name:, participant_id: nil, payload: {})
    return unless application_id.present? && event_type.present? && room_name.present?

    WebrtcAnalyticsWorker.perform_async(
      application_id.to_s,
      event_type,
      room_name.to_s,
      participant_id.to_s.presence,
      payload
    )
  end
end
