# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BeamersController, type: :routing do
  describe 'routing' do
    it 'routes to #index' do
      expect(get: '/tournaments/1/beamers').to route_to(
        'beamers#index', tournament_id: '1'
      )
    end

    it 'routes to #show' do
      expect(get: '/tournaments/1/beamers/2').to route_to(
        'beamers#show', tournament_id: '1', id: '2'
      )
    end

    it 'routes to #by_name' do
      expect(get: '/tournaments/1/beamers/by_name').to route_to(
        'beamers#by_name', tournament_id: '1'
      )
    end

    it 'routes to #create' do
      expect(post: '/tournaments/1/beamers').to route_to(
        'beamers#create', tournament_id: '1'
      )
    end

    it 'routes to #update via PATCH' do
      expect(patch: '/tournaments/1/beamers/2').to route_to(
        'beamers#update', tournament_id: '1', id: '2'
      )
    end

    it 'routes to #destroy' do
      expect(delete: '/tournaments/1/beamers/2').to route_to(
        'beamers#destroy', tournament_id: '1', id: '2'
      )
    end
  end
end
