# JWT generation and verification for WebRTC WebSocket authentication.
#
# Tokens are short-lived (default 24 h) and carry the minimum claims needed
# to authenticate an AnyCable connection without a database lookup.
#
# Usage:
#   token  = WebrtcTokenService.generate(app_id:, room_id:, participant_id:)
#   claims = WebrtcTokenService.decode!(token)   # raises InvalidTokenError on failure
class WebrtcTokenService
  class InvalidTokenError < StandardError; end

  ALGORITHM       = "HS256"
  REQUIRED_CLAIMS = %w[ app_id room_id participant_id ].freeze

  # Returns a signed JWT string.
  def self.generate(app_id:, room_id:, participant_id:, ttl: nil)
    ttl ||= ENV.fetch("WEBRTC_JWT_TTL", 86_400).to_i
    now   = Time.now.to_i

    payload = {
      app_id:         app_id,
      room_id:        room_id,
      participant_id: participant_id,
      iat:            now,
      exp:            now + ttl
    }

    JWT.encode(payload, signing_key, ALGORITHM)
  end

  # Returns the decoded payload hash.
  # Raises InvalidTokenError for any decode failure:
  #   - blank token, expired, tampered signature, missing required claims
  def self.decode!(token)
    raise InvalidTokenError, "Token is blank" if token.blank?

    payload, = JWT.decode(token, signing_key, true, algorithms: [ ALGORITHM ])

    REQUIRED_CLAIMS.each do |claim|
      raise InvalidTokenError, "Missing required claim: #{claim}" if payload[claim].blank?
    end

    payload
  rescue JWT::DecodeError => e
    raise InvalidTokenError, e.message
  end

  private_class_method def self.signing_key
    ENV.fetch("WEBRTC_JWT_SECRET") { Rails.application.secret_key_base }
  end
end
