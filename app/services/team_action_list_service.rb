# frozen_string_literal: true

class TeamActionListService
  GROUP_STAGE_SURVIVOR_PLAYOFF_TOKEN_KEY = 'group_stage_survivor_playoff_tokens'

  class << self
    def ensure_group_stage_survivor_playoff_token_list!(tournament)
      group_stage = tournament.group_stage
      return nil unless group_stage&.finished?

      teams = tournament.teams_advancing_from_group_stage
      return nil if teams.empty?

      ensure_list!(
        tournament: tournament,
        key: GROUP_STAGE_SURVIVOR_PLAYOFF_TOKEN_KEY,
        name: 'Playoff token collection',
        action_name: 'Collect playoff token',
        source: 'group_stage_survivors',
        teams: teams
      )
    end

    def ensure_list!(tournament:, key:, name:, action_name:, source:, teams:)
      list = tournament.team_action_lists.find_or_initialize_by(key: key)
      list.name = name
      list.action_name = action_name
      list.source = source
      list.save!
      list.sync_teams!(teams)
      list
    end
  end
end
