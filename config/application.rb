require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"

Bundler.require(*Rails.groups)

module Konexzero
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])

    # Rate limit headers on API responses (after Rack::Attack)
    require_relative "../app/middleware/rate_limit_headers"
    config.middleware.use RateLimitHeaders

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Use UUID primary keys for all generated models.
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end
  end
end
