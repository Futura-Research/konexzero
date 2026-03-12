source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "jbuilder"
gem "bcrypt", "~> 3.1.7"
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Real-time WebSockets via AnyCable
gem "anycable-rails", "~> 1.5"

# Background jobs
gem "sidekiq", "~> 7.0"
gem "sidekiq-cron", "~> 1.12"

# Redis client
gem "redis", "~> 5.0"
gem "connection_pool", "~> 2.4"

# API rate limiting
gem "rack-cors"
gem "rack-attack", "~> 6.7"

# Structured logging
gem "lograge"

# JWT for WebSocket authentication
gem "jwt"

# Environment variable management
gem "dotenv-rails", groups: %i[development test]

# Reduces boot times through caching
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma
gem "thruster", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"
  gem "faker"
end

group :test do
  gem "vcr"
  gem "webmock"
  gem "shoulda-matchers", "~> 6.0"
  gem "simplecov", require: false
  gem "simplecov-json", require: false
end

group :development do
  gem "web-console"
end
