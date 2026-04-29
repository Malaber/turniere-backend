# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Metrics endpoint', type: :request do
  before do
    MetricsRegistry.reset!
  end

  it 'renders Prometheus text without authentication' do
    get '/metrics'

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to include('text/plain')
    expect(response.body).to include('# TYPE turniere_build_info gauge')
    expect(response.body).to include('# TYPE turniere_http_requests_total counter')
    expect(response.body).to include('turniere_action_cable_connections 0')
  end

  it 'includes request metrics from previous controller requests' do
    get '/healthz'
    get '/metrics'

    expect(response.body).to include(
      'turniere_http_requests_total{method="GET",controller="health",action="index",status="200"} 1'
    )
  end
end
