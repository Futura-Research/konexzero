FactoryBot.define do
  factory :room do
    application
    room_id { "app_test_#{SecureRandom.alphanumeric(12)}_#{Faker::Internet.slug(glue: "-")}" }
    display_name { Faker::Lorem.words(number: 3).join("-") }
    status { :active }
    metadata { {} }
    started_at { Time.current }
    max_participants { nil }
    ended_at { nil }
  end
end
