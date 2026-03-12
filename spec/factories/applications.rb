FactoryBot.define do
  factory :application do
    name { Faker::App.name }
    slug { nil }
    description { Faker::Lorem.sentence }
    metadata { {} }
  end
end
