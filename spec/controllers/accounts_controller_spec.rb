# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountsController, type: :controller do
  describe 'GET #show' do
    let(:account) { create(:user, username: 'player-one') }
    let(:public_team) { create(:team, name: 'Public Team', players: [account]) }
    let(:private_team) { create(:team, name: 'Private Team', players: [account]) }
    let(:public_tournament) { create(:tournament, public: true, teams: [public_team]) }
    let(:private_tournament) { create(:tournament, public: false, teams: [private_team]) }
    let(:created_public_tournament) { create(:tournament, user: account, public: true) }
    let(:created_private_tournament) { create(:tournament, user: account, public: false) }

    before do
      public_tournament
      private_tournament
      created_public_tournament
      created_private_tournament
    end

    it 'returns public account profile information' do
      get :show, params: { id: account.to_param }

      body = deserialize_response(response)
      expect(response).to be_successful
      expect(body[:id]).to eq(account.id)
      expect(body[:name]).to eq('player-one')
      expect(body[:username]).to eq('player-one')
      expect(body[:teams].map { |team| team[:id] }).to eq([public_team.id])
      expect(body[:tournaments].map { |tournament| tournament[:id] }).to eq([public_tournament.id])
      expect(body[:created_tournaments].map { |tournament| tournament[:id] }).to eq([created_public_tournament.id])
    end

    it 'returns private profile information to the account owner' do
      apply_authentication_headers_for account

      get :show, params: { id: account.to_param }

      body = deserialize_response(response)
      expect(body[:teams].map { |team| team[:id] }).to match_array([public_team.id, private_team.id])
      expect(body[:tournaments].map { |tournament| tournament[:id] })
        .to match_array([public_tournament.id, private_tournament.id])
      expect(body[:created_tournaments].map { |tournament| tournament[:id] })
        .to match_array([created_public_tournament.id, created_private_tournament.id])
    end

    it 'returns not found for unknown accounts' do
      get :show, params: { id: User.maximum(:id).to_i + 1 }

      expect(response).to have_http_status(:not_found)
    end
  end
end
