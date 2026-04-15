# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/performance_helpers'

RSpec.describe 'Tournament rendering performance', type: :request do
  [
    { groups_count: 8, teams_per_group: 4, max_duration_ms: 1000 },
    { groups_count: 64, teams_per_group: 6, max_duration_ms: 5000 },
    { groups_count: 4, teams_per_group: 32, max_duration_ms: 5000 }
  ].each do |scenario|
    it "renders #{scenario[:groups_count]} groups with #{scenario[:teams_per_group]} teams within budget" do
      tournament = create_group_stage_tournament(
        groups_count: scenario[:groups_count],
        teams_per_group: scenario[:teams_per_group]
      )

      get "/tournaments/#{tournament.id}"
      expect(response).to have_http_status(:ok)

      performance = capture_runtime_and_queries do
        get "/tournaments/#{tournament.id}", params: { profile: 'true' }
      end

      expect(response).to have_http_status(:ok)
      expect(response.headers['Server-Timing']).to include('load_tournament')
      expect(response.headers['Server-Timing']).to include('serialize_tournament')
      expect(response.headers['X-Turniere-Profile']).to include('tournament.show')
      expect(response.headers['X-Turniere-Profile']).to include('sql')

      body = response.parsed_body
      expect(body.fetch('stages').first.fetch('groups').size).to eq(scenario[:groups_count])
      expect(body.fetch('teams').size).to eq(scenario[:groups_count] * scenario[:teams_per_group])
      expect(performance[:duration_ms]).to be <= scenario[:max_duration_ms]
    end
  end
end
