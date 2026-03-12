require 'simplecov'
require 'simplecov-json'

SimpleCov.start 'rails' do
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/db/'
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter
  ])
end if ENV['COVERAGE']

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
require 'factory_bot_rails'
require 'shoulda/matchers'
require 'vcr'
require 'webmock/rspec'

Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

Shoulda::Matchers.configure do |config|
  config.integrate { |with|
    with.test_framework :rspec
    with.library :rails
  }
end

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data("<CLOUDFLARE_API_TOKEN>") { ENV["CLOUDFLARE_API_TOKEN"] }
  config.filter_sensitive_data("<CLOUDFLARE_ACCOUNT_ID>") { ENV["CLOUDFLARE_ACCOUNT_ID"] }
  config.filter_sensitive_data("<CLOUDFLARE_APP_ID>") { ENV["CLOUDFLARE_APP_ID"] }
  config.filter_sensitive_data("<CLOUDFLARE_TURN_KEY_ID>") { ENV["CLOUDFLARE_TURN_KEY_ID"] }
  config.filter_sensitive_data("<CLOUDFLARE_TURN_KEY_API_TOKEN>") { ENV["CLOUDFLARE_TURN_KEY_API_TOKEN"] }
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.fixture_paths = [
    Rails.root.join("spec/fixtures")
  ]

  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!
end
