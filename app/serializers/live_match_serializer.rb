# frozen_string_literal: true

class LiveMatchSerializer < ApplicationSerializer
  attributes :position, :state, :location, :start_time, :notes, :teams, :group, :stage

  has_many :match_scores

  def teams
    object.teams.map do |team|
      {
        id: team.id,
        name: team.name
      }
    end
  end

  def group
    return nil if object.group.nil?

    {
      id: object.group.id,
      number: object.group.number
    }
  end

  def stage
    stage = object.stage || object.group&.stage
    return nil if stage.nil?

    {
      id: stage.id,
      level: stage.level,
      state: stage.state
    }
  end
end
