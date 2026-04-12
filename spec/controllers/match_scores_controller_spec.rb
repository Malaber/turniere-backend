# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MatchScoresController, type: :controller do
  before do
    @match_score = create(:match_score)
    @owner = @match_score.owner
  end

  describe 'GET #show' do
    it 'returns a success response' do
      get :show, params: { id: @match_score.to_param }
      expect(response).to be_successful
    end

    it 'should return the correct score' do
      get :show, params: { id: @match_score.to_param }
      body = deserialize_response response
      expect(body[:points]).to eq(@match_score.points)
      expect(body[:team][:id]).to eq(@match_score.team.id)
    end
  end

  describe 'PUT #update' do
    let(:valid_update) do
      {
        points: 42,
        hidden_points: 13
      }
    end

    context 'with valid params' do
      context 'as owner' do
        before(:each) do
          apply_authentication_headers_for @owner
        end
        context 'when match_score update succeeds' do
          it 'updates the requested score' do
            put :update, params: { id: @match_score.to_param }.merge(valid_update)
            @match_score.reload
            expect(@match_score.points).to eq(valid_update[:points])
            expect(@match_score.hidden_points).to eq(valid_update[:hidden_points])
          end

          it 'renders a response with the updated team' do
            put :update, params: { id: @match_score.to_param }.merge(valid_update)
            expect(response).to be_successful
            body = deserialize_response response
            expect(body[:points]).to eq(valid_update[:points])
            expect(body[:hidden_points]).to eq(valid_update[:hidden_points])
          end
        end

        context 'when match_score update fails' do
          before do
            allow_any_instance_of(MatchScore)
              .to receive(:update)
              .and_return(false)
          end

          it 'returns unprocessable entity' do
            put :update, params: { id: @match_score.to_param }.merge(valid_update)
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end

      context 'as another user' do
        before(:each) do
          apply_authentication_headers_for create(:user)
        end

        it 'renders a forbidden error response' do
          put :update, params: { id: @match_score.to_param }.merge(valid_update)
          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end

  describe 'on a real tournament' do
    before do
      @owner = create(:user)
      @tournament = create(:group_stage_tournament, stage_count: 0, match_factory: :filled_group_match, owner: @owner)
      @group = @tournament.stages.first.groups.first
      @match_score = @group.matches.first.match_scores.first
    end

    let(:valid_update) do
      {
        points: 42,
        hidden_points: 13
      }
    end

    describe 'updating a match_score' do
      before(:each) do
        apply_authentication_headers_for @owner
        expect(UpdateGroupsGroupScoresAndSave).to receive(:call).once.with(group: @group).and_return(context)
      end

      shared_examples_for 'successful_update_of_match_score' do
        it 'returns a 200 status code' do
          put :update, params: { id: @match_score.to_param }.merge(valid_update)
          expect(response).to be_successful
        end
      end

      context 'when group_score calculation succeeds' do
        let(:context) { double(:context, success?: true) }

        it_should_behave_like 'successful_update_of_match_score'
      end

      context 'when group_score calculation fails' do
        let(:context) { double(:context, success?: false) }

        it_should_behave_like 'successful_update_of_match_score'
      end
    end
  end
end
