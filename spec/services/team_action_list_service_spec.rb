# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamActionListService do
  describe '.create!' do
    let(:tournament) { create(:tournament, teams_count: 4) }

    it 'creates a list with items for all tournament teams' do
      list = described_class.create!(
        tournament:,
        name: 'Team check-in',
        key: 'team_check_in',
        action_name: 'Check in',
        source: 'all_tournament_teams'
      )

      expect(list.team_action_items.includes(:team).map(&:team)).to match_array(tournament.teams)
    end

    it 'creates a list for group stage survivors when available' do
      group_stage_tournament = create(:tournament, teams_count: 0, playoff_teams_amount: 2, instant_finalists_amount: 2)
      group_stage = create(:group_stage, tournament: group_stage_tournament, group_count: 0)
      group = create(:group, stage: group_stage, match_count: 0, number: 1)
      team_a = create(:team, tournament: group_stage_tournament, name: 'A')
      team_b = create(:team, tournament: group_stage_tournament, name: 'B')
      create(:group_score, group:, team: team_a, group_points: 6, scored_points: 6, received_points: 0, position: 1)
      create(:group_score, group:, team: team_b, group_points: 3, scored_points: 3, received_points: 3, position: 2)
      group_stage.update!(state: 'finished')

      list = described_class.create!(
        tournament: group_stage_tournament,
        name: 'Playoff token collection',
        key: 'playoff_token_collection',
        action_name: 'Collect playoff token',
        source: 'group_stage_survivors'
      )

      expect(list.team_action_items.includes(:team).map(&:team)).to match_array([team_a, team_b])
    end

    it 'raises for unsupported source' do
      expect do
        described_class.create!(
          tournament:,
          name: 'Broken',
          key: 'broken',
          action_name: 'Break',
          source: 'unknown_source'
        )
      end.to raise_error(TeamActionListService::InvalidSourceError,
                         'Unsupported team action list source: unknown_source')
    end

    it 'raises when source resolves to no teams' do
      empty_tournament = create(:tournament, teams_count: 0)

      expect do
        described_class.create!(
          tournament: empty_tournament,
          name: 'Empty',
          key: 'empty',
          action_name: 'Nothing',
          source: 'all_tournament_teams'
        )
      end.to raise_error(TeamActionListService::EmptySourceError,
                         'Source all_tournament_teams does not currently contain any teams')
    end
  end
end
