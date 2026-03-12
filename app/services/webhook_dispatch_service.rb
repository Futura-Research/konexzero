class WebhookDispatchService
  def self.dispatch(application:, event_type:, payload:)
    endpoints = application.webhook_endpoints.active.for_event(event_type)
    return if endpoints.none?

    endpoints.find_each do |endpoint|
      event = endpoint.webhook_events.create!(
        event_type: event_type,
        payload: payload,
        status: "pending"
      )
      WebhookDeliveryWorker.perform_async(event.id)
    end
  rescue StandardError => e
    Rails.logger.error("[WebhookDispatchService] #{e.message}")
  end
end
