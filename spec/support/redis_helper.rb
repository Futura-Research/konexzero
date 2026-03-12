RSpec.configure do |config|
  config.before(:each, :redis) do
    WEBRTC_REDIS_POOL.with { |redis| redis.flushdb }
  end
end
