# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GroupsController, type: :controller do
  before do
    @group = create(:group)
  end

  describe 'GET #show' do
    it 'returns a success response' do
      get :show, params: { id: @group.to_param }
      expect(response).to be_successful
    end

    it 'should return the correct group' do
      get :show, params: { id: @group.to_param }
      body = deserialize_response response
      expect(Group.find_by(id: body[:id])).to eq(@group)
      expect(body[:number]).to eq(@group.number)
      expect(body[:matches].size).to eq(@group.matches.size)
      expect(body[:group_scores].size).to eq(@group.group_scores.size)
    end

    it 'returns ranking_decision metadata for group scores' do
      tournament = @group.stage.tournament
      tournament.update!(playoff_teams_amount: 2, instant_finalists_amount: 2, intermediate_round_participants_amount: 0)
      @group.stage.update!(level: -1)
      @group.matches.destroy_all
      @group.group_scores.destroy_all

      team_a = create(:team, tournament: tournament, name: 'A')
      team_b = create(:team, tournament: tournament, name: 'B')

      create(:group_match, group: @group, state: :finished).tap do |match|
        create(:match_score, match: match, team: team_a, points: 3)
        create(:match_score, match: match, team: team_b, points: 1)
      end

      score_a = create(:group_score, group: @group, team: team_a, group_points: 3, scored_points: 3, received_points: 1)
      score_b = create(:group_score, group: @group, team: team_b, group_points: 3, scored_points: 3, received_points: 1)
      GroupStageService.send(:recalculate_position_of_group_scores!, [score_a, score_b]).each(&:save!)

      get :show, params: { id: @group.to_param }
      body = deserialize_response response
      winner = body[:group_scores].find { |score| score.dig(:team, :name) == 'A' }
      loser = body[:group_scores].find { |score| score.dig(:team, :name) == 'B' }

      expect(winner[:ranking_decision]).to include(
        resolved_by: 'direct_comparison',
        compared_with_team_name: 'B',
        direct_comparison_result: 'won',
        tied: false,
        needs_decider_match: false
      )
      expect(loser[:ranking_decision]).to include(
        resolved_by: 'direct_comparison',
        compared_with_team_name: 'A',
        direct_comparison_result: 'lost',
        tied: false,
        needs_decider_match: false
      )
    end
  end
end
