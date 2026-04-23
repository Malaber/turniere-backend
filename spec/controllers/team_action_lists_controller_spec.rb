# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamActionListsController, type: :controller do
  let(:tournament) { create(:tournament, teams_count: 4) }
  let(:team_action_item) { create(:team_action_item) }
  let(:list) { team_action_item.team_action_list }
  let(:team) { team_action_item.team }

  describe 'POST #create' do
    let(:create_params) do
      {
        tournament_id: tournament.to_param,
        name: 'Playoff token collection',
        key: 'playoff_token_collection',
        action_name: 'Collect playoff token',
        source: 'all_tournament_teams'
      }
    end

    context 'as owner' do
      before do
        apply_authentication_headers_for tournament.owner
      end

      it 'creates a list populated from the selected source' do
        post :create, params: create_params

        expect(response).to have_http_status(:created)

        created_list = tournament.team_action_lists.find_by!(key: 'playoff_token_collection')
        expect(created_list.name).to eq('Playoff token collection')
        expect(created_list.action_name).to eq('Collect playoff token')
        expect(created_list.source).to eq('all_tournament_teams')
        expect(created_list.team_action_items.includes(:team).map(&:team)).to match_array(tournament.teams)
      end

      it 'enqueues tournament sync after create' do
        allow(TournamentSyncEnqueue).to receive(:call)

        post :create, params: create_params

        expect(TournamentSyncEnqueue).to have_received(:call).with(tournament)
      end

      it 'returns unprocessable entity for unsupported source' do
        post :create, params: create_params.merge(source: 'unknown_source')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(deserialize_response(response)[:error]).to eq('Unsupported team action list source: unknown_source')
      end

      it 'returns unprocessable entity when selected source resolves to no teams' do
        empty_tournament = create(:tournament, teams_count: 0)
        apply_authentication_headers_for empty_tournament.owner

        post :create, params: create_params.merge(tournament_id: empty_tournament.to_param)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(deserialize_response(response)[:error]).to eq('Source all_tournament_teams does not currently contain any teams')
      end

      it 'returns unprocessable entity for duplicate key' do
        tournament.team_action_lists.create!(
          name: 'Existing list',
          key: 'playoff_token_collection',
          action_name: 'Existing action',
          source: 'all_tournament_teams'
        )

        post :create, params: create_params

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'as another user' do
      before do
        apply_authentication_headers_for create(:user)
      end

      it 'returns forbidden' do
        post :create, params: create_params

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'for follower tournament' do
      before do
        tournament.update!(read_only_mode: true, sync_auth_token: 'sync-token')
        apply_authentication_headers_for tournament.owner
      end

      it 'returns locked' do
        post :create, params: create_params

        expect(response).to have_http_status(:locked)
      end
    end
  end

  describe 'PATCH #update_item' do
    context 'as owner' do
      before do
        apply_authentication_headers_for list.tournament.owner
      end

      it 'updates item by list key and team id' do
        patch :update_item, params: {
          tournament_id: list.tournament.to_param,
          key: list.key,
          team_id: team.to_param,
          completed: true
        }

        expect(response).to be_successful
        expect(team_action_item.reload.completed).to eq(true)
      end

      it 'is idempotent when same state sent repeatedly' do
        2.times do
          patch :update_item, params: {
            tournament_id: list.tournament.to_param,
            key: list.key,
            team_id: team.to_param,
            completed: true
          }
          expect(response).to be_successful
        end

        expect(team_action_item.reload.completed).to eq(true)
      end

      it 'enqueues tournament sync' do
        allow(TournamentSyncEnqueue).to receive(:call)

        patch :update_item, params: {
          tournament_id: list.tournament.to_param,
          key: list.key,
          team_id: team.to_param,
          completed: true
        }

        expect(TournamentSyncEnqueue).to have_received(:call).with(list.tournament)
      end
    end

    context 'as another user' do
      before do
        apply_authentication_headers_for create(:user)
      end

      it 'returns forbidden' do
        patch :update_item, params: {
          tournament_id: list.tournament.to_param,
          key: list.key,
          team_id: team.to_param,
          completed: true
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when list key is missing' do
      before do
        apply_authentication_headers_for list.tournament.owner
      end

      it 'returns not found' do
        patch :update_item, params: {
          tournament_id: list.tournament.to_param,
          key: 'unknown_key',
          team_id: team.to_param,
          completed: true
        }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when team is missing from list context' do
      before do
        apply_authentication_headers_for list.tournament.owner
      end

      it 'returns not found' do
        patch :update_item, params: {
          tournament_id: list.tournament.to_param,
          key: list.key,
          team_id: 999_999_999,
          completed: true
        }

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
