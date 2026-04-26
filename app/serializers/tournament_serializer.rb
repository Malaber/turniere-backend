# frozen_string_literal: true

class TournamentSerializer < SimpleTournamentSerializer
  attributes :description, :playoff_teams_amount,
             :instant_finalists_amount, :intermediate_round_participants_amount
  attribute :read_only_mode, if: :sync_metadata_visible?
  attribute :sync_target_url, if: :sync_metadata_visible?
  attribute :sync_last_push_error, if: :sync_metadata_visible?
  # NEVER expose sync_auth_token anywhere - it should only ever be written to or checked against

  has_many :stages
  has_many :team_action_lists

  attribute :timestamp do
    object.timestamp&.iso8601
  end

  attribute :timer_mode

  attribute :sync_last_pushed_at, if: :sync_metadata_visible? do
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

  def sync_metadata_visible?
    scope.present? && scope == object.owner
  end
end
