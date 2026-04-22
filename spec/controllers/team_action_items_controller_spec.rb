# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamActionItemsController, type: :controller do
  let(:team_action_item) { create(:team_action_item) }

  describe 'PATCH #update' do
    context 'as owner' do
      before do
        apply_authentication_headers_for team_action_item.owner
      end

      it 'ticks item off' do
        patch :update, params: { id: team_action_item.to_param, completed: true }

        expect(response).to be_successful
        expect(team_action_item.reload.completed).to eq(true)
        expect(team_action_item.completed_at).not_to be_nil
      end

      it 'can untick item' do
        team_action_item.update!(completed: true, completed_at: Time.zone.parse('2026-04-22T09:00:00Z'))

        patch :update, params: { id: team_action_item.to_param, completed: false }

        expect(response).to be_successful
        expect(team_action_item.reload.completed).to eq(false)
        expect(team_action_item.completed_at).to be_nil
      end
    end

    context 'as another user' do
      before do
        apply_authentication_headers_for create(:user)
      end

      it 'returns forbidden' do
        patch :update, params: { id: team_action_item.to_param, completed: true }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
