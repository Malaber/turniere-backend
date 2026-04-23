# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamActionListsController, type: :controller do
  let(:team_action_item) { create(:team_action_item) }
  let(:tournament) { team_action_item.tournament }
  let(:list) { team_action_item.team_action_list }
  let(:team) { team_action_item.team }

  describe 'PATCH #update_item' do
    context 'as owner' do
      before do
        apply_authentication_headers_for tournament.owner
      end

      it 'updates item by list key and team id' do
        patch :update_item, params: {
          tournament_id: tournament.to_param,
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
            tournament_id: tournament.to_param,
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
          tournament_id: tournament.to_param,
          key: list.key,
          team_id: team.to_param,
          completed: true
        }

        expect(TournamentSyncEnqueue).to have_received(:call).with(tournament)
      end
    end

    context 'as another user' do
      before do
        apply_authentication_headers_for create(:user)
      end

      it 'returns forbidden' do
        patch :update_item, params: {
          tournament_id: tournament.to_param,
          key: list.key,
          team_id: team.to_param,
          completed: true
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when list key is missing' do
      before do
        apply_authentication_headers_for tournament.owner
      end

      it 'returns not found' do
        patch :update_item, params: {
          tournament_id: tournament.to_param,
          key: 'unknown_key',
          team_id: team.to_param,
          completed: true
        }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when team is missing from list context' do
      before do
        apply_authentication_headers_for tournament.owner
      end

      it 'returns not found' do
        patch :update_item, params: {
          tournament_id: tournament.to_param,
          key: list.key,
          team_id: 999_999_999,
          completed: true
        }

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
