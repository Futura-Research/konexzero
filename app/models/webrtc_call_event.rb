class WebrtcCallEvent < ApplicationRecord
  VALID_EVENT_TYPES = %w[
    participant.joined
    participant.left
    track.published
    track.unpublished
    screenshare.started
    screenshare.stopped
    room.ended
  ].freeze

  # -- Associations --
  belongs_to :application

  # -- Validations --
  validates :event_type, :room_name, presence: true
  validates :event_type, inclusion: { in: VALID_EVENT_TYPES }

  # -- Scopes --
  scope :recent,   -> { order(occurred_at: :desc) }
  scope :for_room, ->(room_name) { where(room_name: room_name) }
  scope :by_type,  ->(event_type) { where(event_type: event_type) }
end
