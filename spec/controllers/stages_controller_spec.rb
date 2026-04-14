# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StagesController, type: :controller do
  let(:stage) do
    create(:playoff_stage)
  end

  describe 'GET #show' do
    it 'returns a success response' do
      get :show, params: { id: stage.to_param }
      expect(response).to be_successful
    end

    it 'should return the correct stage' do
      get :show, params: { id: stage.to_param }
      body = deserialize_response response
      expect(Stage.find_by(id: body[:id])).to eq(stage)
      expect(body[:level]).to eq(stage.level)
      expect(body[:state]).to eq(stage.state)
    end
  end

  describe 'PUT #update' do
    let(:finished) do
      { state: 'finished' }
    end

    context 'group_stage with matches that are done' do
      let(:running_group_stage) do
        create(:group_stage, match_factory: :finished_group_match)
      end

      it 'doesn\'t have any other stages besides it before update' do
        expect(running_group_stage.tournament.stages.size).to eq(1)
      end

      context 'as owner' do
        before(:each) do
          apply_authentication_headers_for running_group_stage.owner
        end

        before do
          put :update, params: { id: running_group_stage.to_param }.merge(finished)
          running_group_stage.reload
        end

        it 'succeeds' do
          expect(response).to be_successful
        end

        it 'stops the stage' do
          expect(running_group_stage.state).to eq('finished')
        end

        it 'adds new stages to the tournament' do
          expect(running_group_stage.tournament.reload.stages.size).to be > 1
        end

        it 'adds the right teams' do
          expect(running_group_stage.tournament.reload.stages.max_by(&:level).teams)
            .to match_array(GroupStageService.get_advancing_teams(running_group_stage))
        end
      end

      context 'as another user' do
        before(:each) do
          apply_authentication_headers_for create(:user)
        end

        it 'returns an error' do
          put :update, params: { id: stage.to_param }.merge(finished)
          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    context 'trying to finish a group stage with unfinished matches' do
      let(:group_stage) do
        create(:group_stage)
      end

      before do
        apply_authentication_headers_for group_stage.owner
        put :update, params: { id: group_stage.to_param }.merge(finished)
      end

      it 'it returns unprocessable entity' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns the correct error' do
        expect(deserialize_response(response)[:error])
          .to eq('Group Stage still has some matches that are not over yet. Finish them to generate playoffs')
      end
    end

    context 'already finished group stage' do
      let(:finished_group_stage) do
        group_stage = create(:group_stage, match_factory: :finished_group_match)
        group_stage.finished!
        group_stage.save!
        group_stage
      end

      before do
        apply_authentication_headers_for finished_group_stage.owner
        put :update, params: { id: finished_group_stage.to_param }.merge(finished)
      end

      it 'it returns unprocessable entity' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns the correct error' do
        expect(deserialize_response(response)[:error]).to eq('Only running group stages can be finished')
      end
    end

    context 'trying to change the state to something other than :finished' do
      let(:group_stage) do
        create(:group_stage)
      end

      before do
        apply_authentication_headers_for group_stage.owner
        put :update, params: { id: group_stage.to_param }.merge(state: 'in_progress')
      end

      it 'it returns unprocessable entity' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns the correct error' do
        expect(deserialize_response(response)[:error]).to eq('The state attribute may only be changed to finished')
      end
    end

    context 'when a tie around the advancing cutoff still needs a decider match' do
      let(:group_stage) do
        create(:group_stage, tournament: create(:tournament, teams_count: 0), group_count: 0)
      end

      before do
        tournament = group_stage.tournament
        tournament.update!(playoff_teams_amount: 1, instant_finalists_amount: 1, intermediate_round_participants_amount: 0)
        group = create(:group, stage: group_stage, match_count: 0, number: 1)
        group_stage.groups = [group]
        team_a = create(:team, tournament: tournament, name: 'A')
        team_b = create(:team, tournament: tournament, name: 'B')
        create(:group_match, group: group, state: :finished).tap do |match|
          create(:match_score, match: match, team: team_a, points: 2)
          create(:match_score, match: match, team: team_b, points: 2)
        end
        score_a = create(:group_score, group: group, team: team_a, group_points: 7, scored_points: 4, received_points: 1)
        score_b = create(:group_score, group: group, team: team_b, group_points: 7, scored_points: 4, received_points: 1)
        GroupStageService.send(:recalculate_position_of_group_scores!, [score_a, score_b]).each(&:save!)

        apply_authentication_headers_for group_stage.owner
        put :update, params: { id: group_stage.to_param }.merge(finished)
      end

      it 'returns unprocessable entity' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns a helpful decider error' do
        body = deserialize_response(response)
        expect(body[:error]).to eq('Playoffs cannot be generated yet because a decider match is required for an advancing place')
        expect(body[:blocking_ties].size).to eq(1)
        expect(body[:blocking_ties].first[:team_names]).to eq(%w[A B])
      end
    end
  end
end
