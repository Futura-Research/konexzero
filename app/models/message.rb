class Message < ApplicationRecord
  VALID_MESSAGE_TYPES = %w[text custom_data system].freeze

  # -- Associations --
  belongs_to :application

  # -- Validations --
  validates :room_name, :message_type, presence: true
  validates :message_type, inclusion: { in: VALID_MESSAGE_TYPES }
  validates :content, presence: true, if: -> { message_type == "text" }
  validates :payload, presence: true, if: -> { message_type == "custom_data" }

  # -- Scopes --
  scope :for_room, ->(room_name) { where(room_name: room_name).where(deleted_at: nil) }
  scope :broadcast_messages, -> { where(recipient_id: nil) }
  scope :before_cursor, ->(msg_id) {
    where("sent_at < (?)", unscoped.select(:sent_at).where(id: msg_id))
  }
  scope :recent_first, -> { order(sent_at: :desc, id: :desc) }
end
