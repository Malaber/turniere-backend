# frozen_string_literal: true

class Team < ApplicationRecord
  belongs_to :tournament, optional: true
  has_many :team_players, dependent: :destroy
  has_many :players, through: :team_players
  has_many :group_scores, dependent: :destroy
  has_many :match_scores, dependent: :destroy
  has_many :bets, dependent: :destroy
  has_many :team_action_items, dependent: :destroy

  validates :name, presence: true

  delegate :owner, to: :tournament, allow_nil: true
end
