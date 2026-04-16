# frozen_string_literal: true

class Beamer < ApplicationRecord
  DEFAULT_NAME = 'default'
  DISPLAY_STATES = %w[
    matches_all matches_in_progress matches_upcoming matches_not_started
    matches_finished groups between_games during_game
  ].freeze

  belongs_to :tournament

  validates :name, presence: true, uniqueness: { scope: :tournament_id }
  validates :display_state, presence: true, inclusion: { in: DISPLAY_STATES }

  delegate :owner, to: :tournament
end
