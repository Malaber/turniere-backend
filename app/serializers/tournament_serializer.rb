# frozen_string_literal: true

class TournamentSerializer < SimpleTournamentSerializer
  attributes :description, :playoff_teams_amount,
             :instant_finalists_amount, :intermediate_round_participants_amount,
             :read_only_mode, :sync_target_url, :sync_last_push_error
             # NEVER expose sync_auth_token anywhere - it should only ever be written to or checked against

  has_many :stages

  attribute :timer_end do
    object.timer_end&.iso8601
  end

  attribute :sync_last_pushed_at do
    object.sync_last_pushed_at&.iso8601
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
