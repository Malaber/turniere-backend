# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BeamersController, type: :controller do
  before do
    @tournament = create(:tournament)
    @owner = @tournament.owner
    @default_beamer = @tournament.beamers.find_by!(name: Beamer::DEFAULT_NAME)
    @beamer = create(:beamer, tournament: @tournament)
  end

  describe 'GET #index' do
    it 'returns all beamers for the tournament' do
      get :index, params: { tournament_id: @tournament.to_param }
      expect(response).to be_successful
      body = deserialize_response response
      expect(body.length).to eq(2)
    end
  end

  describe 'GET #show' do
    it 'returns the beamer' do
      get :show, params: { tournament_id: @tournament.to_param, id: @beamer.to_param }
      expect(response).to be_successful
      body = deserialize_response response
      expect(body[:name]).to eq(@beamer.name)
      expect(body[:display_state]).to eq(@beamer.display_state)
    end

    it 'returns 404 for nonexistent beamer' do
      get :show, params: { tournament_id: @tournament.to_param, id: 999_999 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET #by_name' do
    it 'returns beamer by name' do
      get :by_name, params: { tournament_id: @tournament.to_param, name: @beamer.name }
      expect(response).to be_successful
      body = deserialize_response response
      expect(body[:name]).to eq(@beamer.name)
    end

    it 'falls back to default beamer when name not found' do
      get :by_name, params: { tournament_id: @tournament.to_param, name: 'nonexistent' }
      expect(response).to be_successful
      body = deserialize_response response
      expect(body[:name]).to eq(@default_beamer.name)
    end

    it 'falls back to default beamer when name param is missing' do
      get :by_name, params: { tournament_id: @tournament.to_param }
      expect(response).to be_successful
      body = deserialize_response response
      expect(body[:name]).to eq(Beamer::DEFAULT_NAME)
    end

    it 'returns 404 when all beamers were deleted' do
      empty_tournament = create(:tournament)
      empty_tournament.beamers.destroy_all
      get :by_name, params: { tournament_id: empty_tournament.to_param, name: 'anything' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        name: 'new-beamer',
        display_state: 'during_game',
        config: { match_filter: 'state:in_progress' }
      }
    end

    context 'as owner' do
      before(:each) { apply_authentication_headers_for @owner }

      it 'creates a new beamer' do
        expect {
          post :create, params: { tournament_id: @tournament.to_param }.merge(valid_params)
        }.to change(@tournament.beamers, :count).by(1)
        expect(response).to have_http_status(:created)
      end

      it 'returns the created beamer' do
        post :create, params: { tournament_id: @tournament.to_param }.merge(valid_params)
        body = deserialize_response response
        expect(body[:name]).to eq('new-beamer')
        expect(body[:display_state]).to eq('during_game')
        expect(body[:config]).to eq(match_filter: 'state:in_progress')
      end

      it 'rejects invalid display_state' do
        post :create, params: {
          tournament_id: @tournament.to_param, name: 'bad', display_state: 'invalid'
        }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'rejects duplicate name in same tournament' do
        post :create, params: {
          tournament_id: @tournament.to_param, name: @beamer.name, display_state: 'during_game'
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'as another user' do
      before(:each) { apply_authentication_headers_for create(:user) }

      it 'returns forbidden' do
        post :create, params: { tournament_id: @tournament.to_param }.merge(valid_params)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'unauthenticated' do
      it 'returns unauthorized' do
        post :create, params: { tournament_id: @tournament.to_param }.merge(valid_params)
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH #update' do
    context 'as owner' do
      before(:each) { apply_authentication_headers_for @owner }

      it 'updates the display_state' do
        patch :update, params: {
          tournament_id: @tournament.to_param, id: @beamer.to_param,
          display_state: 'during_game'
        }
        expect(response).to be_successful
        body = deserialize_response response
        expect(body[:display_state]).to eq('during_game')
        expect(@beamer.reload.display_state).to eq('during_game')
      end

      it 'replaces config' do
        @beamer.update!(config: { match_filter: 'state:upcoming', image_key: 'old-logo' })

        patch :update, params: {
          tournament_id: @tournament.to_param, id: @beamer.to_param,
          config: { image_key: 'bpwstr_logo' }
        }
        expect(response).to be_successful
        body = deserialize_response response
        expect(body[:config]).to eq(image_key: 'bpwstr_logo')
        @beamer.reload
        expect(@beamer.config).to eq('image_key' => 'bpwstr_logo')
      end

      it 'rejects invalid display_state' do
        patch :update, params: {
          tournament_id: @tournament.to_param, id: @beamer.to_param,
          display_state: 'bogus'
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'as another user' do
      before(:each) { apply_authentication_headers_for create(:user) }

      it 'returns forbidden' do
        patch :update, params: {
          tournament_id: @tournament.to_param, id: @beamer.to_param,
          display_state: 'group_tables'
        }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'on read only follower tournament' do
      before(:each) do
        @tournament.update!(read_only_mode: true, sync_auth_token: 'shared-secret')
        apply_authentication_headers_for @owner
      end

      it 'returns locked' do
        patch :update, params: {
          tournament_id: @tournament.to_param, id: @beamer.to_param,
          display_state: 'group_tables'
        }
        expect(response).to have_http_status(:locked)
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'as owner' do
      before(:each) { apply_authentication_headers_for @owner }

      it 'deletes the beamer' do
        expect {
          delete :destroy, params: {
            tournament_id: @tournament.to_param, id: @beamer.to_param
          }
        }.to change(@tournament.beamers, :count).by(-1)
        expect(response).to have_http_status(:no_content)
      end
    end

    context 'as another user' do
      before(:each) { apply_authentication_headers_for create(:user) }

      it 'returns forbidden' do
        delete :destroy, params: {
          tournament_id: @tournament.to_param, id: @beamer.to_param
        }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
