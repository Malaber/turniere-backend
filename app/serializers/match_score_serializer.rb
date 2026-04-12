# frozen_string_literal: true

class MatchScoreSerializer < ApplicationSerializer
  attributes :points, :hidden_points

  belongs_to :team
end
