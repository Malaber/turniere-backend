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
  end
end
