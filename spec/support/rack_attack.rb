RSpec.configure do |config|
  config.before(:each) do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end
end
