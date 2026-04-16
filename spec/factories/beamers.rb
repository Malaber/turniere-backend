# frozen_string_literal: true

FactoryBot.define do
  factory :beamer do
    sequence(:name) { |n| "beamer-#{n}" }
    display_state { 'matches_all' }
    tournament

    factory :default_beamer do
      name { 'default' }
    end
  end
end
