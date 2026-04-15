# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatisticsController, type: :controller do
  describe 'GET #index' do
    context 'tournament without a group stage' do
      it 'returns a not implemented response' do
        get :index, params: { tournament_id: create(:tournament).to_param }
        expect(response).to have_http_status(:not_implemented)
      end
    end

    context 'tournament with a group stage' do
      before do
        @tournament = create(:group_stage_tournament, stage_count: 0)
        @group_stage = @tournament.stages.find_by(level: -1)
        @most_dominant_score = create(:group_score,
                                      team: @tournament.teams.first,
                                      group_points: 100,
                                      scored_points: 100, received_points: 0)
        @least_dominant_score = create(:group_score,
                                       team: @tournament.teams.first,
                                       group_points: 0,
                                       scored_points: 0, received_points: 100)
        @tournament.stages.first.groups.first.group_scores << @most_dominant_score
        @tournament.stages.first.groups.first.group_scores << @least_dominant_score
        @tournament.save!
      end

      it 'returns a success response' do
        get :index, params: { tournament_id: @tournament.to_param }
        expect(response).to be_successful
      end

      it 'returns a list containing all group scores' do
        get :index, params: { tournament_id: @tournament.to_param }
        expected_count = @group_stage.groups.sum { |group| group.group_scores.size }
        expect(deserialize_response(response)[:group_scores].length).to eq(expected_count)
      end

      it 'returns a most dominant group score' do
        get :index, params: { tournament_id: @tournament.to_param }
        expect(deserialize_response(response)[:most_dominant_score][:id]).to eq(@most_dominant_score.id)
      end

      it 'returns a least dominant group score' do
        get :index, params: { tournament_id: @tournament.to_param }
        expect(deserialize_response(response)[:least_dominant_score][:id]).to eq(@least_dominant_score.id)
      end
    end
  end
end
