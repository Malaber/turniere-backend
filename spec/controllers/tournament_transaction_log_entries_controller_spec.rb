# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentTransactionLogEntriesController, type: :controller do
  let(:tournament) { create(:tournament) }
  let(:owner) { tournament.owner }

  before do
    TournamentTransactionLogger.record!(
      tournament: tournament,
      user: owner,
      action: 'test.entry',
      message: 'owner changed match 1',
      metadata: { match_id: 1 }
    )
  end

  describe 'GET #index' do
    context 'as owner' do
      before do
        apply_authentication_headers_for owner
      end

      it 'returns ordered transaction log entries' do
        get :index, params: { id: tournament.to_param }

        expect(response).to be_successful
        body = deserialize_response(response)
        expect(body.size).to eq(1)
        expect(body.first[:sequence]).to eq(1)
        expect(body.first[:action]).to eq('test.entry')
        expect(body.first[:message]).to eq('owner changed match 1')
        expect(body.first[:metadata]).to eq(match_id: 1)
      end
    end

    context 'as another user' do
      before do
        apply_authentication_headers_for create(:user)
      end

      it 'returns forbidden' do
        get :index, params: { id: tournament.to_param }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
