# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MatchesController, type: :routing do
  describe 'routing' do
    it 'routes to #show' do
      expect(get: '/matches/1').to route_to('matches#show', id: '1')
    end

    it 'routes nested group matches to #create' do
      expect(post: '/groups/1/matches').to route_to('matches#create', group_id: '1')
    end

    it 'routes to #swap' do
      expect(patch: '/matches/1/swap').to route_to('matches#swap', id: '1')
    end

    it 'routes nested tournament match metadata updates' do
      expect(patch: '/tournaments/1/matches/metadata').to route_to('matches#metadata', tournament_id: '1')
    end
  end
end
