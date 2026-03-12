class ApiCredential < ApplicationRecord
  APP_ID_PREFIX = "app_"
  SECRET_KEY_PREFIX = "sk_live_"
  APP_ID_RANDOM_LENGTH = 24
  SECRET_KEY_RANDOM_LENGTH = 48

  # -- Associations --
  belongs_to :application

  # -- Validations --
  validates :app_id, presence: true, uniqueness: true
  validates :secret_key_digest, presence: true
  validates :secret_key_prefix, presence: true

  # -- Scopes --
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :not_expired, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }

  # Generates a new credential for the given application.
  # Returns [credential, raw_secret] — the raw secret is only available here.
  def self.generate_for(application, label: nil, expires_at: nil)
    raw_secret = "#{SECRET_KEY_PREFIX}#{SecureRandom.alphanumeric(SECRET_KEY_RANDOM_LENGTH)}"

    credential = new(
      application: application,
      app_id: generate_unique_app_id,
      secret_key_digest: BCrypt::Password.create(raw_secret, cost: 12),
      secret_key_prefix: raw_secret[0, 12],
      label: label,
      expires_at: expires_at
    )

    credential.save!
    [ credential, raw_secret ]
  end

  # Looks up a credential by app_id and verifies the raw secret.
  # Returns the credential on success, nil on failure.
  # This is the single entry point for API authentication.
  def self.authenticate(app_id, raw_secret)
    credential = active.not_expired
                       .eager_load(:application)
                       .find_by(app_id: app_id)
    return nil unless credential&.authenticate(raw_secret)

    credential
  end

  # Verifies a raw secret against this credential's BCrypt digest.
  def authenticate(raw_secret)
    return false unless active?
    return false if expired?

    BCrypt::Password.new(secret_key_digest).is_password?(raw_secret)
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def deactivate!
    update!(active: false)
  end

  # Skips callbacks and validations for a lightweight timestamp update.
  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  def self.generate_unique_app_id
    loop do
      candidate = "#{APP_ID_PREFIX}#{SecureRandom.alphanumeric(APP_ID_RANDOM_LENGTH)}"
      return candidate unless exists?(app_id: candidate)
    end
  end
  private_class_method :generate_unique_app_id
end
