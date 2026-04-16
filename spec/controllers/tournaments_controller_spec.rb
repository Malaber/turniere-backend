# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentsController, type: :controller do
  before do
    @tournament = create(:tournament)
    @user = @tournament.owner
    @another_user = create(:user)
    @private_tournament = create(:tournament, user: @another_user, public: false)
    @teams = create_list(:team, 4)
    @teams16 = create_list(:team, 16)
    @groups = create_list(:group, 4)
  end

  describe 'GET #index' do
    context 'without parameters' do
      it 'returns a success response' do
        get :index
        expect(response).to be_successful
      end

      it 'returns all public tournaments' do
        get :index
        tournaments = deserialize_response response
        public_tournaments = tournaments.select { |t| t[:public] }
        expect(public_tournaments.map { |t| t[:id] }).to match_array(Tournament.where(public: true).map { |t| t[:id] })
      end
    end

    context 'with type=private parameter' do
      let(:params) do
        { type: 'private' }
      end

      it 'returns all private tournaments' do
        apply_authentication_headers_for @another_user
        get :index, params: params
        tournaments = deserialize_response response
        private_tournaments = Tournament.where(owner: @another_user, public: false).map { |t| t[:id] }
        returned_private_tournaments = tournaments.filter { |t| !t[:public] }.map { |t| t[:id] }
        expect(returned_private_tournaments).to match_array(private_tournaments)
      end

      it 'returns no private tournaments for unauthenticated users' do
        get :index, params: params
        tournaments = deserialize_response response
        private_tournaments = tournaments.reject { |t| t[:public] }
        expect(private_tournaments.size).to eq(0)
      end

      it 'returns no private tournaments owned by another user' do
        apply_authentication_headers_for @user
        get :index, params: params
        tournaments = deserialize_response response
        expect(tournaments.map { |t| t[:id] }).not_to include(@private_tournament.id)
      end

      it 'returns no public tournaments' do
        apply_authentication_headers_for @another_user
        get :index, params: params
        tournaments = deserialize_response response
        expect(tournaments.count { |t| t[:public] }).to eq(0)
      end
    end

    context 'with type=public parameter' do
      let(:params) do
        { type: 'public' }
      end

      it 'returns all public tournaments' do
        get :index, params: params
        tournaments = deserialize_response response
        public_tournaments = tournaments.select { |t| t[:public] }
        expect(public_tournaments.map { |t| t[:id] }).to match_array(Tournament.where(public: true).map { |t| t[:id] })
      end

      it 'returns no private tournaments' do
        apply_authentication_headers_for @another_user
        get :index, params: params
        tournaments = deserialize_response response
        expect(tournaments.count { |t| !t[:public] }).to eq(0)
      end
    end

    context 'with invalid type parameter' do
      it 'renders a bad request error response' do
        put :index, params: { type: 'invalid' }
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'GET #show' do
    it 'returns a success response' do
      get :show, params: { id: @tournament.to_param }
      expect(response).to be_successful
    end

    it 'returns the requested tournament' do
      get :show, params: { id: @tournament.to_param }
      json = deserialize_response(response)
      expect(json[:id].to_i).to eq(@tournament.id)
      expected_keys = %i[id name code public description playoff_teams_amount instant_finalists_amount intermediate_round_participants_amount timer_end owner_username stages teams]
      expect(json.keys).to match_array(expected_keys)
      expect(json).to eq(TournamentSerializer.new(@tournament).as_json)
      expect(json[:name]).to eq(@tournament.name)
      expect(json[:description]).to eq(@tournament.description)
      expect(json[:public]).to eq(@tournament.public)
    end

    context 'with simple=true parameter' do
      it 'returns no relations' do
        get :show, params: { id: @tournament.to_param, simple: 'true' }
        body = deserialize_response response
        expect(body[:stages]).to be_nil
        expect(body[:teams]).to be_nil
      end
    end

    context 'with profile=true parameter' do
      it 'adds profiling headers outside production' do
        get :show, params: { id: @tournament.to_param, profile: 'true' }

        expect(response.headers['Server-Timing']).to include('load_tournament')
        expect(response.headers['Server-Timing']).to include('serialize_tournament')
        expect(response.headers['X-Turniere-Profile']).to include('tournament.show')
      end

      it 'ignores profiling in production' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

        get :show, params: { id: @tournament.to_param, profile: 'true' }

        expect(response.headers['Server-Timing']).to be_nil
        expect(response.headers['X-Turniere-Profile']).to be_nil
      end
    end

    context 'on a group stage tournament' do
      before do
        @group_stage_tournament = create(:group_stage_tournament)
      end

      it 'includes advancing teams' do
        # take 4 of the teams in the tournament and set them as advancing teams
        expected_advancing_teams = @group_stage_tournament.teams.take(4)
        allow(GroupStageService).to receive(:get_advancing_teams).and_return(expected_advancing_teams)

        get :show, params: { id: @group_stage_tournament.to_param }
        body = deserialize_response response
        # get the advancing teams from the teams array in the response ( they have advancing_from_group_stage = true )
        advancing_teams = body[:teams].select { |team| team[:advancing_from_group_stage] }
        # check array is not empty
        expect(advancing_teams).not_to be_empty

        # cast json to teams and compare
        advancing_teams = advancing_teams.map { |team| Team.find(team[:id]) }
        expect(advancing_teams).to match_array(expected_advancing_teams)
      end
    end
  end

  describe 'GET #timer_end' do
    it 'returns timer_end in ISO 8601 format' do
      timer_end = Time.utc(2026, 4, 13, 18, 0, 0)
      @tournament.update!(timer_end: timer_end)

      get :timer_end, params: { id: @tournament.to_param }

      expect(response).to be_successful
      expect(deserialize_response(response)[:timer_end]).to eq(timer_end.iso8601)
    end
  end

  describe 'PATCH #set_timer_end' do
    before(:each) do
      apply_authentication_headers_for @user
    end

    it 'stores timezone-aware timer_end values without shifting them' do
      timer_end = '2030-04-13T18:00:00+02:00'

      patch :set_timer_end, params: { id: @tournament.to_param, timer_end: timer_end }

      expect(response).to be_successful
      expect(@tournament.reload.timer_end.iso8601).to eq(Time.iso8601(timer_end).utc.iso8601)
      expect(deserialize_response(response)[:timer_end]).to eq(@tournament.timer_end.iso8601)
    end
  end

  describe 'POST #create' do
    let(:create_playoff_tournament_data) do
      {
        name: Faker::Creature::Dog.name,
        description: Faker::Lorem.sentence,
        public: false,
        teams: @teams.map { |team| { id: team.id } }
      }
    end

    let(:create_group_tournament_data) do
      teams_with_groups = @teams16.each_with_index.map { |team, i| { id: team.id, group: (i / 4).floor } }
      {
        name: Faker::TvShows::FamilyGuy.character,
        description: Faker::Movies::HarryPotter.quote,
        public: false,
        group_stage: true,
        teams: teams_with_groups,
        playoff_teams_amount: (@teams16.size / 2)
      }
    end

    context 'without authentication headers' do
      it 'renders an unauthorized error response' do
        put :create, params: create_playoff_tournament_data
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with authentication headers' do
      before(:each) do
        apply_authentication_headers_for @user
      end

      context 'with read_only_mode=true' do
        it 'creates an empty follower tournament without teams payload' do
          expect do
            post :create, params: {
              name: 'Follower Tournament',
              public: false,
              read_only_mode: true,
              sync_auth_token: 'shared-secret'
            }
          end.to change(Tournament, :count).by(1)

          expect(response).to have_http_status(:created)
          tournament = Tournament.find(deserialize_response(response)[:id])
          expect(tournament.read_only_mode?).to eq(true)
          expect(tournament.teams).to be_empty
          expect(tournament.stages).to be_empty
        end
      end

      context 'with existing teams' do
        it 'creates a new Tournament' do
          expect do
            post :create, params: create_playoff_tournament_data
          end.to change(Tournament, :count).by(1)
        end

        it 'associates the new tournament with the authenticated user' do
          expect do
            post :create, params: create_playoff_tournament_data
          end.to change(@user.tournaments, :count).by(1)
        end

        it 'associates the given teams with the created tournament' do
          post :create, params: create_playoff_tournament_data
          body = deserialize_response response
          tournament = Tournament.find(body[:id])
          expect(tournament.teams).to match_array(@teams)
        end

        it 'generates a playoff stage' do
          post :create, params: create_playoff_tournament_data
          body = deserialize_response response
          tournament = Tournament.find(body[:id])
          expect(tournament.stages.first).to be_a(Stage)
        end

        it 'generates a playoff stage with all given teams' do
          post :create, params: create_playoff_tournament_data
          body = deserialize_response response
          tournament = Tournament.find(body[:id])
          included_teams = tournament.stages.first.matches.map { |m| m.match_scores.map(&:team) }.flatten.uniq
          expect(included_teams).to match_array(@teams)
        end

        it 'creates a default beamer automatically' do
          post :create, params: create_playoff_tournament_data
          body = deserialize_response response
          tournament = Tournament.find(body[:id])

          expect(tournament.beamers.pluck(:name)).to include(Beamer::DEFAULT_NAME)
        end

        context 'with parameter group_stage=true' do
          before do
            post :create, params: create_group_tournament_data
            body = deserialize_response response
            @group_stage_tournament = Tournament.find(body[:id])
          end

          it 'generates a group stage with all teams given in parameters' do
            included_teams = @group_stage_tournament.stages.find_by(level: -1).teams
            expect(included_teams).to match_array(@teams16)
          end

          it 'generates a group stage' do
            group_stage = @group_stage_tournament.stages.find_by(level: -1)
            expect(group_stage).to be_a(Stage)
          end

          it 'saves the amount of teams that advance into playoffs' do
            expect(@group_stage_tournament.playoff_teams_amount)
              .to eq(create_group_tournament_data[:playoff_teams_amount])
          end

          it 'associates the given teams with the created tournament' do
            expect(@group_stage_tournament.teams).to match_array(@teams16)
          end

          context 'playoff_teams_amount unacceptable' do
            shared_examples_for 'wrong playoff_teams_amount' do
              it 'fails' do
                expect(response).to have_http_status(:unprocessable_entity)
              end
              it 'returns the correct error message' do
                expect(deserialize_response(response)[:playoff_teams_amount].first)
                  .to eq('playoff_teams_amount needs to be a positive power of two')
              end
            end

            context 'is not a power of two' do
              before do
                post :create, params: create_group_tournament_data.merge(playoff_teams_amount: 18)
              end

              it_should_behave_like 'wrong playoff_teams_amount'
            end

            context 'isn\'t positive' do
              before do
                post :create, params: create_group_tournament_data.merge(playoff_teams_amount: -16)
              end

              it_should_behave_like 'wrong playoff_teams_amount'
            end

            context 'isn\'t positive nor a power of two' do
              before do
                post :create, params: create_group_tournament_data.merge(playoff_teams_amount: -42)
              end

              it_should_behave_like 'wrong playoff_teams_amount'
            end
          end
        end

        it 'renders a JSON response with the new tournament' do
          post :create, params: create_playoff_tournament_data
          expect(response).to have_http_status(:created)
          expect(response.media_type).to eq('application/json')
          expect(response.location).to eq(tournament_url(Tournament.last))
        end
      end

      context 'with missing teams' do
        it 'returns an error response' do
          data = create_playoff_tournament_data
          data[:teams] << { id: Team.last.id + 1 }
          post :create, params: data
          expect(response).to have_http_status(:not_found)
        end
      end

      context 'with unequal group sizes' do
        it 'returns an error response' do
          data = create_group_tournament_data
          data[:teams].pop
          post :create, params: data
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'with team names' do
        it 'creates teams for given names' do
          data = create_playoff_tournament_data
          data.delete :teams
          data[:teams] = (1..12).collect { { name: Faker::Creature::Dog.name } }
          expect do
            post :create, params: data
          end.to change(Team, :count).by(data[:teams].count)
        end
      end

      context 'with invalid parameters' do
        it 'renders an unprocessable entity response' do
          put :create, params: { teams: [1, 2, 3] }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'with empty team objects' do
        it 'renders an unprocessable entity response' do
          data = create_group_tournament_data
          data[:teams] = [{ group: 1 }, { group: 1 }, { group: 2 }, { group: 2 }]
          post :create, params: data
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end
  end

  describe 'PUT #update' do
    let(:valid_update) do
      {
        name: Faker::Creature::Dog.name
      }
    end

    context 'with valid params' do
      context 'without authentication headers' do
        it 'renders a unauthorized error response' do
          put :update, params: { id: @tournament.to_param }.merge(valid_update)
          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'as owner' do
        before(:each) do
          apply_authentication_headers_for @tournament.owner
        end

        it 'updates the requested tournament' do
          put :update, params: { id: @tournament.to_param }.merge(valid_update)
          @tournament.reload
          expect(@tournament.name).to eq(valid_update[:name])
        end

        it 'renders a JSON response with the tournament' do
          put :update, params: { id: @tournament.to_param }.merge(valid_update)
          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq('application/json')
        end

        it 'allows sync config changes on read only tournaments' do
          @tournament.update!(read_only_mode: true, sync_auth_token: 'old-token')

          put :update, params: {
            id: @tournament.to_param,
            read_only_mode: false,
            sync_target_url: 'https://remote.example.com/tournaments/1/sync_state',
            sync_auth_token: 'new-token'
          }

          expect(response).to have_http_status(:ok)
          @tournament.reload
          expect(@tournament.read_only_mode?).to eq(false)
          expect(@tournament.sync_target_url).to include('/sync_state')
          expect(@tournament.sync_auth_token).to eq('new-token')
        end

        it 'allows follower takeover when only read_only_mode is disabled' do
          @tournament.update!(read_only_mode: true, sync_auth_token: 'old-token')
          request.headers['CONTENT_TYPE'] = 'application/json'

          put :update, params: {
            id: @tournament.to_param,
            read_only_mode: false
          }, as: :json

          expect(response).to have_http_status(:ok)
          @tournament.reload
          expect(@tournament.read_only_mode?).to eq(false)
          expect(@tournament.sync_target_url).to be_blank
          expect(@tournament.sync_auth_token).to be_blank
        end

        it 'blocks normal updates while tournament is read only' do
          @tournament.update!(read_only_mode: true, sync_auth_token: 'shared-secret')

          put :update, params: { id: @tournament.to_param, name: 'Should Not Work' }

          expect(response).to have_http_status(:locked)
          expect(deserialize_response(response)[:error]).to eq('Tournament is in read only follower mode')
        end

        context 'any variable relevant for group stage to playoff transition changed' do
          before(:each) do
            @filled_tournament = create(:group_stage_tournament)
            apply_authentication_headers_for @filled_tournament.owner
          end

          it 'fails when only instant_finalists_amount is changed' do
            put :update, params: { id: @filled_tournament.to_param }.merge(instant_finalists_amount: 29)
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'fails when only intermediate_round_participants_amount is changed' do
            put :update, params: { id: @filled_tournament.to_param }.merge(intermediate_round_participants_amount: 29)
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'fails when parameters don\'t match' do
            put :update, params: { id: @filled_tournament.to_param }.merge(intermediate_round_participants_amount: 29,
                                                                           instant_finalists_amount: 32)
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'succeeds when all three are changed correctly' do
            allow(GroupStageService).to receive(:get_advancing_teams).and_return(@filled_tournament.teams.take(4))
            put :update, params: { id: @filled_tournament.to_param }.merge(intermediate_round_participants_amount: 2,
                                                                           instant_finalists_amount: 1,
                                                                           playoff_teams_amount: 2)
          end

          context 'only playoff_teams_amount is changed reasonably but update fails' do
            before do
              allow_any_instance_of(Tournament)
                .to receive(:update)
                .and_return(false)
            end

            it 'returns unprocessable entity' do
              put :update, params: { id: @filled_tournament.to_param }.merge(playoff_teams_amount: 8)
              expect(response).to have_http_status(:unprocessable_entity)
            end

            it 'doesn\'t change playoff_teams_amount' do
              expect do
                put :update, params: { id: @filled_tournament.to_param }.merge(playoff_teams_amount: 8)
                @filled_tournament.reload
              end
                .to_not(change { @filled_tournament.playoff_teams_amount })
            end

            it 'doesn\'t change instant_finalists_amount' do
              expect do
                put :update, params: { id: @filled_tournament.to_param }.merge(playoff_teams_amount: 8)
                @filled_tournament.reload
              end
                .to_not(change { @filled_tournament.instant_finalists_amount })
            end

            it 'doesn\'t change intermediate_round_participants_amount' do
              expect do
                put :update, params: { id: @filled_tournament.to_param }.merge(playoff_teams_amount: 8)
                @filled_tournament.reload
              end
                .to_not(change { @filled_tournament.intermediate_round_participants_amount })
            end
          end

          context 'only playoff_teams_amount is changed to something reasonable' do
            before do
              put :update, params: { id: @filled_tournament.to_param }.merge(playoff_teams_amount: 8)
              @filled_tournament.reload
            end

            it 'succeeds' do
              expect(response).to have_http_status(:ok)
            end

            it 'changes playoff_teams_amount' do
              expect(@filled_tournament.playoff_teams_amount).to eq(8)
            end

            it 'adapts instant_finalists_amount' do
              expect(@filled_tournament.instant_finalists_amount).to eq(8)
            end

            it 'adapts intermediate_round_participants_amount' do
              expect(@filled_tournament.intermediate_round_participants_amount).to eq(0)
            end
          end

          it 'fails when playoff_teams_amount is higher than the amount of teams participating' do
            put :update, params: { id: @filled_tournament.to_param }.merge(playoff_teams_amount: 783)
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end

      context 'as another user' do
        before do
          apply_authentication_headers_for create(:user)
        end

        it 'renders a forbidden error response' do
          put :update, params: { id: @tournament.to_param }.merge(valid_update)
          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'without authentication headers' do
      it 'renders a unauthorized error response' do
        delete :destroy, params: { id: @tournament.to_param }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'as owner' do
      before(:each) do
        apply_authentication_headers_for @tournament.owner
      end

      it 'destroys the requested tournament' do
        expect do
          delete :destroy, params: { id: @tournament.to_param }
        end.to change(Tournament, :count).by(-1)
      end

      it 'destroys associated teams' do
        expect do
          delete :destroy, params: { id: @tournament.to_param }
        end.to change(Team, :count).by(-@tournament.teams.size)
      end

      it 'blocks destroy while tournament is read only' do
        @tournament.update!(read_only_mode: true, sync_auth_token: 'shared-secret')

        delete :destroy, params: { id: @tournament.to_param }

        expect(response).to have_http_status(:locked)
      end
    end

    context 'as another user' do
      before do
        apply_authentication_headers_for create(:user)
      end

      it 'renders a forbidden error response' do
        delete :destroy, params: { id: @tournament.to_param }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH #sync_state' do
    before do
      @tournament.update!(read_only_mode: true, sync_auth_token: 'shared-secret')
    end

    it 'imports a pushed snapshot' do
      request.headers['Authorization'] = 'Bearer shared-secret'

      patch :sync_state, params: {
        id: @tournament.to_param,
        snapshot: {
          id: 123,
          name: 'Synced Tournament',
          code: 'abc123',
          description: 'Synced description',
          public: true,
          playoff_teams_amount: 4,
          instant_finalists_amount: 4,
          intermediate_round_participants_amount: 0,
          timer_end: nil,
          teams: [{ id: 7, name: 'Alpha' }],
          stages: [],
          groups: [],
          matches: [],
          match_scores: [],
          group_scores: []
        }
      }

      expect(response).to have_http_status(:ok)
      @tournament.reload
      expect(@tournament.sync_source_tournament_id).to eq(123)
      expect(@tournament.name).to eq('Synced Tournament')
      expect(@tournament.teams.pluck(:name)).to eq(['Alpha'])
    end

    it 'rejects invalid tokens' do
      request.headers['Authorization'] = 'Bearer wrong-token'

      patch :sync_state, params: {
        id: @tournament.to_param,
        snapshot: { id: 123 }
      }

      expect(response).to have_http_status(:unauthorized)
      expect(deserialize_response(response)[:error]).to eq('Invalid sync token')
    end
  end
end
