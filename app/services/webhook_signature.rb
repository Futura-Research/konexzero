class WebhookSignature
  ALGORITHM = "sha256"

  def self.generate(payload:, secret:, timestamp:)
    signed_payload = "#{timestamp}.#{payload}"
    digest = OpenSSL::HMAC.hexdigest(ALGORITHM, secret, signed_payload)
    "#{ALGORITHM}=#{digest}"
  end

  def self.verify(payload:, secret:, timestamp:, signature:)
    expected = generate(payload: payload, secret: secret, timestamp: timestamp)
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end
end
