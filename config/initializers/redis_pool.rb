# Dedicated Redis connection pool for WebRTC state management.
#
# Separate from Sidekiq's pool to allow independent sizing:
# - Sidekiq's pool is sized to its concurrency (5 by default)
# - WebRTC pool is sized for Puma threads + headroom for Sidekiq workers
#
# Uses the same Redis URL as Sidekiq (db 0). Keys are prefixed with "kz:"
# to prevent collision with Sidekiq keys.
WEBRTC_REDIS_POOL = ConnectionPool.new(size: Integer(ENV.fetch("WEBRTC_REDIS_POOL_SIZE", 10))) do
  Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
end
