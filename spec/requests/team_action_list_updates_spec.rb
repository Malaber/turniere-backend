# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Team action list updates', type: :request do
  let(:team_action_item) { create(:team_action_item) }
  let(:list) { team_action_item.team_action_list }
  let(:team) { team_action_item.team }
  let(:owner_headers) { list.tournament.owner.create_new_auth_token }

  describe 'PATCH /team_action_items/:id' do
    it 'returns not found when the item is missing' do
      patch '/team_action_items/999999999',
            params: { completed: true },
            headers: owner_headers,
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.fetch('error')).to include("Couldn't find TeamActionItem")
    end

    it 'updates an existing item' do
      patch "/team_action_items/#{team_action_item.id}",
            params: { completed: true },
            headers: owner_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(team_action_item.reload.completed).to eq(true)
    end
  end

  describe 'PATCH /tournaments/:tournament_id/team_action_lists/:key/teams/:team_id' do
    it 'returns not found when the list key is missing' do
      patch "/tournaments/#{list.tournament.id}/team_action_lists/unknown_key/teams/#{team.id}",
            params: { completed: true },
            headers: owner_headers,
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.fetch('error')).to include("Couldn't find TeamActionList")
    end

    it 'returns not found when the team is missing from the list context' do
      patch "/tournaments/#{list.tournament.id}/team_action_lists/#{list.key}/teams/999999999",
            params: { completed: true },
            headers: owner_headers,
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.fetch('error')).to include("Couldn't find TeamActionItem")
    end
  end
end
