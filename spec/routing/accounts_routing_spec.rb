# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountsController, type: :routing do
  describe 'routing' do
    it 'routes to #show' do
      expect(get: '/accounts/1').to route_to('accounts#show', id: '1')
    end
  end
end
