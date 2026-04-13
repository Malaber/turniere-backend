# frozen_string_literal: true

FactoryBot.define do
  factory :beamer do
    sequence(:name) { |n| "beamer-#{n}" }
    display_state { 'matches_all' }
    is_default { false }
    tournament

    factory :default_beamer do
      name { 'default' }
      is_default { true }
    end
  end
end
