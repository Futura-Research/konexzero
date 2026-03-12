FactoryBot.define do
  factory :webhook_endpoint do
    association :application
    url { "https://example.com/webhooks" }
    subscribed_events { [ "room.started", "room.ended" ] }
    active { true }
    description { "Test webhook endpoint" }
  end
end
