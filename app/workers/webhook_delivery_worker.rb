class WebhookDeliveryWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: false

  CONNECT_TIMEOUT = 10
  READ_TIMEOUT = 30

  def perform(webhook_event_id)
    event = WebhookEvent.find_by(id: webhook_event_id)
    return unless event

    endpoint = event.webhook_endpoint
    return unless endpoint.active?

    deliver(event, endpoint)
  rescue StandardError => e
    Rails.logger.error("[WebhookDeliveryWorker] Event #{webhook_event_id}: #{e.message}")
  end

  private

  def deliver(event, endpoint)
    payload_json = event.payload.to_json
    timestamp = Time.current.to_i.to_s

    signature = WebhookSignature.generate(
      payload: payload_json,
      secret: endpoint.secret,
      timestamp: timestamp
    )

    response = post_webhook(endpoint.url, payload_json, {
      "Content-Type" => "application/json",
      "X-KonexZero-Signature" => signature,
      "X-KonexZero-Event" => event.event_type,
      "X-KonexZero-Delivery" => event.id,
      "X-KonexZero-Timestamp" => timestamp,
      "User-Agent" => "KonexZero-Webhooks/1.0"
    })

    if response.is_a?(Net::HTTPSuccess)
      event.mark_delivered!(response_code: response.code.to_i)
    else
      handle_failure(event, response.code.to_i, response.body)
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
    handle_failure(event, nil, e.message)
  end

  def post_webhook(url, body, headers)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = CONNECT_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri)
    headers.each { |k, v| request[k] = v }
    request.body = body

    http.request(request)
  end

  def handle_failure(event, response_code, response_body)
    event.mark_failed!(response_code: response_code, response_body: response_body)

    if event.attempts < WebhookEvent::MAX_ATTEMPTS
      delay = event.next_retry_delay
      self.class.perform_in(delay, event.id)
    end
  end
end
