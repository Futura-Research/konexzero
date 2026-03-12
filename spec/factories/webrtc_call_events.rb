FactoryBot.define do
  factory :webrtc_call_event do
    association :application
    event_type  { "participant.joined" }
    room_name   { "room-#{SecureRandom.hex(4)}" }
    occurred_at { Time.current }
    payload     { {} }
  end
end
