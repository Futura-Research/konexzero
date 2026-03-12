FactoryBot.define do
  factory :webhook_event do
    association :webhook_endpoint
    event_type { "room.started" }
    payload { { room_id: "test-room", application_id: SecureRandom.uuid } }
    status { "pending" }
    attempts { 0 }
  end
end
