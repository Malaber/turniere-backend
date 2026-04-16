# frozen_string_literal: true

class TournamentSerializer < SimpleTournamentSerializer
  attributes :description, :playoff_teams_amount,
             :instant_finalists_amount, :intermediate_round_participants_amount
  has_many :stages

  attribute :timer_end do
    object.timer_end&.iso8601
  end

  attribute :owner_username do
    object.owner.username
  end

  attribute :teams do
    adv_teams = object.group_stage ? GroupStageService.get_advancing_teams(object.group_stage) : []
    object.teams.map do |team|
      {
        id: team.id,
        name: team.name,
        advancing_from_group_stage: adv_teams.include?(team)
      }
    end
  end
end
