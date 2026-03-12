# Cloudflare Realtime SFU and TURN credentials.
#
# In production, these MUST be set — the initializer will raise on boot if missing.
# In development/test, they can be empty (specs use WebMock, not real API calls).
Rails.application.config.cloudflare = ActiveSupport::OrderedOptions.new.tap do |cf|
  # SFU (Calls) credentials
  cf.app_id    = ENV.fetch("CLOUDFLARE_APP_ID", nil)
  cf.api_token = ENV.fetch("CLOUDFLARE_API_TOKEN", nil)

  # TURN credentials
  cf.turn_key_id        = ENV.fetch("CLOUDFLARE_TURN_KEY_ID", nil)
  cf.turn_key_api_token = ENV.fetch("CLOUDFLARE_TURN_KEY_API_TOKEN", nil)

  # Validate in production — missing credentials = immediate boot failure
  if Rails.env.production?
    %w[CLOUDFLARE_APP_ID CLOUDFLARE_API_TOKEN CLOUDFLARE_TURN_KEY_ID CLOUDFLARE_TURN_KEY_API_TOKEN].each do |var|
      raise "Missing required environment variable: #{var}" if ENV[var].blank?
    end
  end
end
