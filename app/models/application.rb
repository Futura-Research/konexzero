# NOTE: The name `Application` does not conflict with `Rails::Application` because
# ActiveRecord models resolve in the global namespace as `::Application`. This naming
# is idiomatic for a "developer app" entity (used by GitHub, Shopify, Stripe).
class Application < ApplicationRecord
  # -- Associations --
  has_many :api_credentials, dependent: :restrict_with_error
  has_one :active_credential, -> { where(active: true).order(created_at: :desc) }, class_name: "ApiCredential"
  has_many :rooms, dependent: :restrict_with_error
  has_many :webhook_endpoints, dependent: :destroy

  # -- Validations --
  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true,
                   uniqueness: true,
                   length: { maximum: 63 },
                   format: {
                     with: /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/,
                     message: "must be lowercase alphanumeric with optional hyphens"
                   }

  # -- Scopes --
  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }

  # -- Callbacks --
  before_validation :generate_slug, on: :create, if: -> { slug.blank? }

  # -- Soft delete --
  def discard
    update(discarded_at: Time.current)
  end

  def undiscard
    update(discarded_at: nil)
  end

  def discarded?
    discarded_at.present?
  end

  private

  def generate_slug
    base = name&.parameterize
    return unless base.present?

    self.slug = base
    counter = 1
    while self.class.exists?(slug: slug)
      self.slug = "#{base}-#{counter}"
      counter += 1
    end
  end
end
