# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamActionItemsController, type: :routing do
  describe 'routing' do
    it 'routes to #update via PATCH' do
      expect(patch: '/team_action_items/1').to route_to('team_action_items#update', id: '1')
    end
  end
end
