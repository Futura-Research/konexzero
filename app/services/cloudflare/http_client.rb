module Cloudflare
  class HttpClient
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    MAX_RETRIES  = 3
    RETRY_DELAY  = 0.5 # seconds (base — actual delay is RETRY_DELAY * 2^attempt)

    # ── Error hierarchy ──────────────────────────────────────────────
    class ApiError < StandardError
      attr_reader :status, :body

      def initialize(message = nil, status: nil, body: nil)
        @status = status
        @body = body
        super(message || "Cloudflare API error (HTTP #{status})")
      end
    end

    class SessionNotFoundError < ApiError
      def initialize(body: nil)
        super("Cloudflare session not found", status: 404, body: body)
      end
    end

    class RateLimitError < ApiError
      def initialize(body: nil)
        super("Cloudflare rate limit exceeded", status: 429, body: body)
      end
    end

    private

    def http_post(url, body)
      http_request(:post, url, body)
    end

    def http_put(url, body)
      http_request(:put, url, body)
    end

    def http_get(url)
      http_request(:get, url)
    end

    def http_request(method, url, body = nil)
      attempt = 0

      begin
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        req = build_request(method, uri, body)
        response = http.request(req)

        instrument(method, url, response.code.to_i)
        handle_response(response, method, url)
      rescue ApiError => e
        raise unless retryable?(e.status)

        attempt += 1
        if attempt < MAX_RETRIES
          delay = RETRY_DELAY * (2**attempt)
          Rails.logger.warn(
            "[#{self.class.name}] Retry #{attempt}/#{MAX_RETRIES} " \
            "for #{method.upcase} #{url} (#{e.status}) — backoff #{delay}s"
          )
          sleep(delay)
          retry
        end

        Rails.logger.error(
          "[#{self.class.name}] Max retries exhausted for #{method.upcase} #{url} (#{e.status})"
        )
        raise
      end
    end

    def build_request(method, uri, body)
      req = case method
      when :post then Net::HTTP::Post.new(uri)
      when :put  then Net::HTTP::Put.new(uri)
      when :get  then Net::HTTP::Get.new(uri)
      else raise ArgumentError, "Unsupported HTTP method: #{method}"
      end

      req["Authorization"] = "Bearer #{api_token}"
      if body
        req["Content-Type"] = "application/json"
        req.body = body.to_json
      end
      req
    end

    def handle_response(response, method, url)
      code = response.code.to_i
      return JSON.parse(response.body) if code >= 200 && code < 300

      Rails.logger.error("[#{self.class.name}] #{method.upcase} #{url} returned #{code}: #{response.body}")

      case code
      when 404 then raise SessionNotFoundError.new(body: response.body)
      when 429 then raise RateLimitError.new(body: response.body)
      else raise ApiError.new(status: code, body: response.body)
      end
    end

    def retryable?(status)
      status.to_i >= 500 && status.to_i < 600
    end

    def instrument(method, url, status)
      ActiveSupport::Notifications.instrument("request.cloudflare", {
        method: method,
        url: url,
        status: status,
        service: self.class.name
      })
    end

    # Subclasses must implement this to return their Bearer token.
    def api_token
      raise NotImplementedError, "#{self.class.name} must implement #api_token"
    end
  end
end
