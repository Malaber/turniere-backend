# frozen_string_literal: true

require 'rails_helper'

def test_get_index_with_filter(filter_state)
  get :index, params: { state: filter_state, tournament_id: @tournament.to_param }
  deserialize_response(response).each do |match|
    expect(match[:state]).to eq(filter_state)
  end
end

RSpec.describe MatchesController, type: :controller do
  before do
    @match = create(:match, state: :not_started)
    @amount_of_stages = 2
    @tournament = create(:stage_tournament, stage_count: @amount_of_stages)
    @running_playoff_match = @tournament.stages.find_by(level: @amount_of_stages).matches.first
    @not_ready_playoff_match = create(:running_playoff_match, state: :not_ready)
    @match.match_scores = create_pair(:match_score)
  end

  describe 'GET #index' do
    context 'on a running group stage' do
      before do
        @tournament = create(:group_stage_tournament, match_factory: :running_group_match)
        @tournament.matches.each_with_index do |m, i|
          m.state = :not_started if i.even?
          m.save!
        end
      end

      it 'filters running matches when told to do so' do
        test_get_index_with_filter('running')
      end

      it 'filters not_started matches when told to do so' do
        test_get_index_with_filter('not_started')
      end

      it 'doesn\'t break if the filter contains rubbish' do
        get :index, params: { state: 'saftladen', tournament_id: @tournament.to_param }
        body = deserialize_response response
        expect(body.empty?).to be true
      end
    end
    # TODO add test for upcoming once there is test data for a "valid" group stage
  end

  describe 'GET #show' do
    it 'should return success' do
      get :show, params: { id: @match.to_param }
      expect(response).to be_successful
      expect(response.media_type).to eq('application/json')
    end

    it 'should return the correct state' do
      get :show, params: { id: @match.to_param }
      body = deserialize_response response
      expect(body[:state]).to eq(@match.state)
      expect(body[:match_scores].map { |ms| ms[:id] }).to eq(@match.match_scores.map(&:id))
    end
  end

  describe 'POST #create' do
    let(:group_stage_tournament) { create(:group_stage_tournament, group_count: 1, match_factory: :finished_group_match) }
    let(:group) { group_stage_tournament.stages.find_by(level: -1).groups.first }
    let(:team_ids) { group.teams.first(2).map(&:id) }

    context 'as owner' do
      before do
        apply_authentication_headers_for group.owner
      end

      it 'creates a decider match at the end of the group' do
        expect do
          post :create, params: { group_id: group.to_param, team_ids: team_ids }
        end.to change { group.matches.reload.count }.by(1)

        expect(response).to have_http_status(:created)
        created_match = group.matches.reload.max_by(&:position)
        expect(created_match.decider?).to eq(true)
        expect(created_match.state).to eq('not_started')
        expect(created_match.teams.map(&:id)).to match_array(team_ids)
      end
    end

    context 'with invalid teams' do
      before do
        apply_authentication_headers_for group.owner
      end

      it 'rejects the request' do
        post :create, params: { group_id: group.to_param, team_ids: [group.teams.first.id] }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST #update' do
    context 'on a running playoff match' do
      let(:valid_update) do
        {
          state: 'in_progress'
        }
      end

      let(:invalid_update) do
        {
          state: 'finished'
        }
      end

      let(:senseless_update) do
        {
          state: 'not_ready'
        }
      end

      context 'as owner' do
        before(:each) do
          apply_authentication_headers_for @match.owner
        end

        context 'with valid params' do
          it 'updates the match' do
            put :update, params: { id: @match.to_param }.merge(valid_update)
            @match.reload
            expect(response).to be_successful
            expect(@match.state).to eq(valid_update[:state])
          end

          it 'renders a response with the updated match' do
            put :update, params: { id: @match.to_param }.merge(valid_update)
            expect(response).to be_successful
            body = deserialize_response response
            expect(body[:state]).to eq(valid_update[:state])
          end

          context 'on a running playoff match' do
            let(:finished) do
              {
                state: 'finished'
              }
            end

            before(:each) do
              apply_authentication_headers_for @running_playoff_match.owner
            end

            context 'match update succeeds' do
              context 'on a decided match' do
                before do
                  @running_playoff_match.match_scores.each_with_index do |ms, i|
                    ms.points = i
                    ms.save!
                  end
                  put :update, params: { id: @running_playoff_match.to_param }.merge(finished)
                  @running_playoff_match.reload
                end

                it 'updates the matches status' do
                  expect(response).to be_successful
                  expect(@running_playoff_match.state).to eq(finished[:state])
                end

                describe 'updates the match below' do
                  before do
                    @match_below = @tournament.stages.find_by(level: @amount_of_stages - 1).matches
                                              .find_by(position: @running_playoff_match.position / 2).reload
                  end

                  it 'with the right teams' do
                    expect(@running_playoff_match.winner).to be_a(Team)
                    expect(@match_below.teams).to include(@running_playoff_match.winner)
                  end

                  it 'with the right status' do
                    expect(@match_below.state).to eq('not_ready')
                  end
                end
              end

              context 'on an undecided match' do
                before do
                  @running_playoff_match.match_scores.each do |ms|
                    ms.points = 42
                    ms.save!
                  end
                  put :update, params: { id: @running_playoff_match.to_param }.merge(finished)
                  @running_playoff_match.reload
                end

                it 'returns an unprocessable entity response' do
                  expect(response).to have_http_status(:unprocessable_entity)
                end

                it 'doesn\'t change the matches status' do
                  expect(@running_playoff_match.state).to eq('in_progress')
                end

                describe 'doesn\'t update the match below' do
                  before do
                    @match_below = @tournament.stages.find_by(level: @amount_of_stages - 1).matches
                                              .find_by(position: @running_playoff_match.position / 2).reload
                  end

                  it 'teams' do
                    expect(@match_below.teams.empty?).to be(true)
                  end

                  it 'status' do
                    expect(@match_below.state).to eq('not_ready')
                  end
                end
              end
            end

            context 'match update fails' do
              before do
                allow_any_instance_of(Match)
                  .to receive(:update)
                  .and_return(false)
              end

              it 'returns unprocessable entity' do
                put :update, params: { id: @running_playoff_match.to_param }.merge(finished)
                expect(response).to have_http_status(:unprocessable_entity)
              end
            end

            context 'PopulateMatchBelowAndSave fails' do
              before do
                expect(PopulateMatchBelowAndSave).to receive(:call).once.with(
                  match: have_attributes(id: @running_playoff_match.id)
                )
                                                                   .and_return(context)
              end

              context 'when unsuccessful' do
                let(:context) { double(:context, success?: false) }

                it 'returns unprocessable entity' do
                  # mock match.winner to be the first team of the match to skip winner check here
                  allow_any_instance_of(Match).to receive(:winner).and_return(@running_playoff_match.match_scores.first.team)

                  put :update, params: { id: @running_playoff_match.to_param }.merge(finished)
                  expect(response).to have_http_status(:unprocessable_entity)
                end
              end
            end

            context 'on the last match in the tournament' do
              let(:updated_finale) do
                only_final_tournament = create(:stage_tournament, stage_count: 1)
                finale = only_final_tournament.stages.first.matches.first

                finale.match_scores.each_with_index do |ms, i|
                  ms.points = i
                  ms.save!
                end

                apply_authentication_headers_for finale.owner
                put :update, params: { id: finale.to_param }.merge(finished)
                finale.reload
              end

              it 'response is successful' do
                expect(response).to be_successful
              end

              it 'updates the matches status' do
                expect(updated_finale.state).to eq(finished[:state])
              end
            end
          end
        end

        context 'with invalid params' do
          it 'renders an unprocessable entity response' do
            put :update, params: { id: @match.to_param }.merge(invalid_update)
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end

        context 'with senseless params' do
          it 'renders an unprocessable entity response' do
            put :update, params: { id: @match.to_param }.merge(senseless_update)
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end

      context 'as another user' do
        context 'with valid params' do
          before(:each) do
            apply_authentication_headers_for create(:user)
          end

          it 'renders a forbidden error response' do
            put :update, params: { id: @match.to_param }.merge(valid_update)
            expect(response).to have_http_status(:forbidden)
          end
        end
      end
    end

    context 'on a playoff match that isn\'t ready yet' do
      let(:invalid_update) do
        {
          state: 'in_progress'
        }
      end

      context 'as owner' do
        before(:each) do
          apply_authentication_headers_for @not_ready_playoff_match.owner
        end

        context 'with invalid params' do
          it 'renders an unprocessable entity response' do
            put :update, params: { id: @not_ready_playoff_match.to_param }.merge(invalid_update)
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end
    end
  end
end
