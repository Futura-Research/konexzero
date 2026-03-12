class Rack::Attack
  # Use Redis for throttle storage (shared across web processes)
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    namespace: "rack_attack"
  )

  # ── Throttles ─────────────────────────────────────────────

  # 1. Per-credential: 120 req/min for all API endpoints
  throttle("api/credential", limit: 120, period: 1.minute) do |req|
    req.env["HTTP_X_APP_ID"] if req.path.start_with?("/api/v1")
  end

  # 2. Signaling-specific: 60 req/min per credential
  SIGNALING_PATHS = %w[join publish unpublish subscribe unsubscribe renegotiate leave].freeze

  throttle("api/signaling", limit: 60, period: 1.minute) do |req|
    if req.path.start_with?("/api/v1/rooms/") && req.post? &&
       SIGNALING_PATHS.any? { |p| req.path.end_with?("/#{p}") || req.path.include?("/#{p}/") }
      req.env["HTTP_X_APP_ID"]
    end
  end

  # 3. Unauthenticated: 30 req/min per IP
  throttle("api/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/v1") && req.env["HTTP_X_APP_ID"].blank?
  end

  # ── Throttled Response ────────────────────────────────────

  self.throttled_responder = lambda do |req|
    match_data = req.env["rack.attack.match_data"] || {}
    now = Time.current
    retry_after = (match_data[:period] || 60).to_i

    body = {
      type: "https://docs.konexzero.com/errors/rate-limited",
      title: "Too Many Requests",
      status: 429,
      detail: "Rate limit exceeded. Maximum #{match_data[:limit]} requests per #{retry_after} seconds.",
      suggestion: "Reduce request frequency or contact support for higher limits.",
      docs: "https://docs.konexzero.com/errors/rate-limited"
    }.to_json

    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_s,
        "X-RateLimit-Limit" => match_data[:limit].to_s,
        "X-RateLimit-Remaining" => "0",
        "X-RateLimit-Reset" => (now + retry_after.seconds).to_i.to_s
      },
      [ body ]
    ]
  end
end
