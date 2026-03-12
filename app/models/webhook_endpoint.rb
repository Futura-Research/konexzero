class WebhookEndpoint < ApplicationRecord
  VALID_EVENT_TYPES = %w[room.started room.ended participant.joined participant.left].freeze

  # -- Associations --
  belongs_to :application
  has_many :webhook_events, dependent: :destroy

  # -- Validations --
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid HTTP(S) URL" }
  validates :secret, presence: true
  validates :subscribed_events, presence: true
  validate :validate_event_types

  # -- Scopes --
  scope :active, -> { where(active: true) }
  scope :for_event, ->(event_type) { where("? = ANY(subscribed_events)", event_type) }

  # -- Callbacks --
  before_validation :generate_secret, on: :create

  private

  def generate_secret
    self.secret ||= SecureRandom.hex(32)
  end

  def validate_event_types
    return if subscribed_events.blank?

    invalid = subscribed_events - VALID_EVENT_TYPES
    return if invalid.empty?

    errors.add(:subscribed_events, "contains invalid event types: #{invalid.join(', ')}")
  end
end
