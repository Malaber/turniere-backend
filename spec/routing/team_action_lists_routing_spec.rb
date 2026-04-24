# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamActionListsController, type: :routing do
  describe 'routing' do
    it 'routes to #create via POST' do
      expect(post: '/tournaments/1/team_action_lists')
        .to route_to('team_action_lists#create', tournament_id: '1')
    end

    it 'routes to #update_item via PATCH' do
      expect(patch: '/tournaments/1/team_action_lists/playoff_token_collection/teams/2')
        .to route_to(
          'team_action_lists#update_item',
          tournament_id: '1',
          key: 'playoff_token_collection',
          team_id: '2'
        )
    end
  end
end
