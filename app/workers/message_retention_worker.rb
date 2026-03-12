class MessageRetentionWorker
  include Sidekiq::Worker

  sidekiq_options queue: :low, retry: 1

  RETENTION_DAYS = Integer(ENV.fetch("MESSAGE_RETENTION_DAYS", 30))
  RECOVERY_WINDOW_DAYS = 7

  def perform
    soft_delete_expired_messages
    hard_delete_recovered_messages
  end

  private

  def soft_delete_expired_messages
    Message
      .where(deleted_at: nil)
      .where("sent_at < ?", RETENTION_DAYS.days.ago)
      .update_all(deleted_at: Time.current)
  end

  def hard_delete_recovered_messages
    Message
      .where("deleted_at < ?", RECOVERY_WINDOW_DAYS.days.ago)
      .delete_all
  end
end
