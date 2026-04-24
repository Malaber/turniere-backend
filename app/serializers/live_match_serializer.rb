# frozen_string_literal: true

class LiveMatchSerializer < ApplicationSerializer
  attributes :position, :state, :teams

  has_many :match_scores

  def teams
    object.teams.map do |team|
      {
        id: team.id,
        name: team.name
      }
    end
  end
end
