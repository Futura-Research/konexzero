FactoryBot.define do
  factory :api_credential do
    application
    app_id { "app_#{SecureRandom.alphanumeric(24)}" }
    secret_key_digest { BCrypt::Password.create("sk_live_test_secret_for_specs", cost: 4) }
    secret_key_prefix { "sk_live_test" }
    label { "Test Key" }
    active { true }
    last_used_at { nil }
    expires_at { nil }
  end
end
