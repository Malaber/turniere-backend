# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamActionListsController, type: :routing do
  describe 'routing' do
    it 'routes to #update_item via PATCH' do
      expect(patch: '/tournaments/1/team_action_lists/group_stage_survivor_playoff_tokens/teams/2')
        .to route_to(
          'team_action_lists#update_item',
          tournament_id: '1',
          key: 'group_stage_survivor_playoff_tokens',
          team_id: '2'
        )
    end
  end
end
