# frozen_string_literal: true

FactoryBot.define do
  factory :beamer do
    sequence(:name) { |n| "beamer-#{n}" }
    display_state { 'during_game' }
    config { {} }
    tournament

    factory :default_beamer do
      name { Beamer::DEFAULT_NAME }

      initialize_with do
        tournament.beamers.find_or_initialize_by(name: name)
      end
    end
  end
end
