# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetricsController, type: :routing do
  describe 'routing' do
    it 'routes to #index' do
      expect(get: '/metrics').to route_to('metrics#index')
    end
  end
end
