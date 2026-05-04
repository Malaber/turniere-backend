# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamsController, type: :controller do
  before do
    @team = create(:tournament).teams.first
    @owner = @team.owner
  end

  describe 'GET #show' do
    it 'returns a success response' do
      get :show, params: { id: @team.to_param }
      expect(response).to be_successful
    end

    it 'should return the correct team' do
      get :show, params: { id: @team.to_param }
      body = deserialize_response response
      expect(body[:name]).to eq(@team.name)
    end

    it 'returns player account summaries when linked' do
      player = create(:user, username: 'linked-player')
      @team.players << player

      get :show, params: { id: @team.to_param }

      body = deserialize_response response
      expect(body[:players].first[:id]).to eq(player.id)
      expect(body[:players].first[:name]).to eq('linked-player')
    end
  end

  describe 'PUT #update' do
    let(:valid_update) do
      {
        name: Faker::Creature::Dog.name
      }
    end

    context 'with valid params as owner' do
      before(:each) do
        apply_authentication_headers_for @owner
      end

      it 'updates the requested team' do
        put :update, params: { id: @team.to_param }.merge(valid_update)
        @team.reload
        expect(response).to be_successful
        expect(@team.name).to eq(valid_update[:name])
      end

      it 'renders a response with the updated team' do
        put :update, params: { id: @team.to_param }.merge(valid_update)
        expect(response).to be_successful
        body = deserialize_response response
        expect(body[:name]).to eq(valid_update[:name])
      end

      it 'associates an existing player account by email' do
        player = create(:user, username: 'player-account', email: 'player@example.com')

        put :update, params: { id: @team.to_param, player_email: player.email }

        expect(response).to be_successful
        expect(@team.reload.players).to contain_exactly(player)
        expect(deserialize_response(response)[:players].first[:id]).to eq(player.id)
      end

      it 'creates a player account by email when none exists' do
        expect do
          put :update, params: { id: @team.to_param, player_email: 'new-player@example.com' }
        end.to change(User, :count).by(1)

        expect(response).to be_successful
        expect(@team.reload.players.first.email).to eq('new-player@example.com')
        expect(@team.players.first.username).to eq('new-player')
      end

      it 'associates multiple player accounts by email' do
        first_player = create(:user, email: 'first-player@example.com')

        put :update, params: {
          id: @team.to_param,
          player_emails: [first_player.email, 'second-player@example.com']
        }

        expect(response).to be_successful
        expect(@team.reload.players.map(&:email)).to match_array(
          ['first-player@example.com', 'second-player@example.com']
        )
      end

      it 'clears player associations with blank player_id' do
        @team.players << create(:user)

        put :update, params: { id: @team.to_param, player_id: '' }

        expect(response).to be_successful
        expect(@team.reload.players).to be_empty
      end
    end

    context 'with valid params as another user' do
      before(:each) do
        apply_authentication_headers_for create(:user)
      end

      it 'renders a forbidden error response' do
        put :update, params: { id: @team.to_param }.merge(valid_update)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with valid params as linked player' do
      before(:each) do
        @player = create(:user)
        @team.players << @player
        apply_authentication_headers_for @player
      end

      it 'updates the requested team name' do
        put :update, params: { id: @team.to_param }.merge(valid_update)

        expect(response).to be_successful
        expect(@team.reload.name).to eq(valid_update[:name])
      end

      it 'cannot reassign the linked player' do
        new_player = create(:user, email: 'other-player@example.com')

        put :update, params: { id: @team.to_param, player_email: new_player.email }

        expect(response).to have_http_status(:forbidden)
        expect(@team.reload.players).to contain_exactly(@player)
      end
    end
  end
end
