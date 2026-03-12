class Room < ApplicationRecord
  # -- Associations --
  belongs_to :application

  # -- Enums --
  enum :status, { active: 0, ended: 1 }, default: :active

  # -- Validations --
  validates :room_id, presence: true, uniqueness: true
  validates :display_name, presence: true, length: { maximum: 255 }
  validates :max_participants, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # -- Scopes --
  scope :chronological, -> { order(created_at: :desc) }
  scope :stale, ->(threshold = 2.hours.ago) { active.where(updated_at: ...threshold) }

  # Creates a tenant-namespaced room for the given application.
  # The room_id is globally unique: "{app_id}_{caller_name}".
  def self.create_for(application:, name:, metadata: {}, max_participants: nil)
    credential = application.api_credentials.active.first
    namespaced_id = build_room_id(credential&.app_id || application.id, name)

    create!(
      application: application,
      room_id: namespaced_id,
      display_name: name,
      metadata: metadata,
      max_participants: max_participants,
      started_at: Time.current
    )
  end

  def self.find_or_create_for(application:, name:, metadata: {}, max_participants: nil)
    credential = application.api_credentials.active.first
    namespaced_id = build_room_id(credential&.app_id || application.id, name)

    active.find_by(room_id: namespaced_id) ||
      create!(
        application: application,
        room_id: namespaced_id,
        display_name: name,
        metadata: metadata,
        max_participants: max_participants,
        started_at: Time.current
      )
  rescue ActiveRecord::RecordNotUnique
    active.find_by!(room_id: namespaced_id)
  end

  def end_room!
    archived_room_id = "#{room_id}#ended_#{Time.current.to_i}"
    update!(status: :ended, ended_at: Time.current, room_id: archived_room_id)
  end

  def self.find_active_for(app_id:, name:)
    active.find_by(room_id: build_room_id(app_id, name))
  end

  def self.build_room_id(app_id, room_name)
    "#{app_id}_#{room_name}"
  end
  private_class_method :build_room_id
end
