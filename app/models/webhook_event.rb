class WebhookEvent < ApplicationRecord
  MAX_ATTEMPTS = 5
  BACKOFF_SCHEDULE = [ 30.seconds, 2.minutes, 15.minutes, 1.hour, 4.hours ].freeze

  # -- Associations --
  belongs_to :webhook_endpoint

  # -- Validations --
  validates :event_type, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending delivered failed] }

  # -- Scopes --
  scope :pending, -> { where(status: "pending") }
  scope :delivered, -> { where(status: "delivered") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }
  scope :retryable, -> { where(status: "pending").where("attempts < ?", MAX_ATTEMPTS) }

  def next_retry_delay
    BACKOFF_SCHEDULE[attempts - 1] || BACKOFF_SCHEDULE.last
  end

  def mark_delivered!(response_code:)
    update!(
      status: "delivered",
      response_code: response_code,
      delivered_at: Time.current,
      attempts: attempts + 1,
      last_attempted_at: Time.current
    )
  end

  def mark_failed!(response_code: nil, response_body: nil)
    new_attempts = attempts + 1
    new_status = new_attempts >= MAX_ATTEMPTS ? "failed" : "pending"

    update!(
      status: new_status,
      response_code: response_code,
      response_body: response_body&.truncate(1024),
      attempts: new_attempts,
      last_attempted_at: Time.current
    )
  end
end
