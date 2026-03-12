class HealthController < ActionController::API
  def show
    checks = {
      database: database_alive?,
      redis: redis_alive?
    }
    status = checks.values.all? ? :ok : :service_unavailable

    render json: { status: status == :ok ? "ok" : "degraded", checks: checks },
           status: status
  end

  private

  def database_alive?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end

  def redis_alive?
    Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0")).ping == "PONG"
  rescue StandardError
    false
  end
end
