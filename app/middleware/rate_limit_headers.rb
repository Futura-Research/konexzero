class RateLimitHeaders
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    if env["PATH_INFO"]&.start_with?("/api/v1") && status != 429
      throttle_data = env["rack.attack.throttle_data"]
      if throttle_data.present?
        most_restrictive = throttle_data.min_by do |_name, data|
          remaining = (data[:limit] || 0) - (data[:count] || 0)
          remaining
        end

        if most_restrictive
          _name, data = most_restrictive
          limit = data[:limit] || 0
          count = data[:count] || 0
          period = data[:period] || 60
          remaining = [ limit - count, 0 ].max

          headers["X-RateLimit-Limit"] = limit.to_s
          headers["X-RateLimit-Remaining"] = remaining.to_s
          headers["X-RateLimit-Reset"] = (Time.current + period.seconds).to_i.to_s
        end
      end
    end

    [ status, headers, body ]
  end
end
