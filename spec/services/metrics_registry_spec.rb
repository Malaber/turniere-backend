# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetricsRegistry do
  let(:health_labels) { 'method="GET",controller="health",action="index",status="200"' }

  before do
    described_class.reset!
  end

  describe '.record_http_request' do
    it 'renders Prometheus counters and duration histogram buckets' do
      described_class.record_http_request(
        method: 'get',
        controller: 'health',
        action: 'index',
        status: 200,
        duration: 0.012
      )

      metrics = described_class.render_prometheus

      expect(metrics).to include(
        "turniere_http_requests_total{#{health_labels}} 1"
      )
      expect(metrics).to include(
        "turniere_http_request_duration_seconds_bucket{#{health_labels},le=\"0.025\"} 1"
      )
      expect(metrics).to include(
        "turniere_http_request_duration_seconds_count{#{health_labels}} 1"
      )
      expect(metrics).to match(
        /turniere_http_request_duration_seconds_sum\{#{health_labels}\} 0\.012/
      )
    end
  end

  describe 'ActionCable connection metrics' do
    it 'tracks open and total websocket connections' do
      described_class.action_cable_connected
      described_class.action_cable_connected
      described_class.action_cable_disconnected

      metrics = described_class.render_prometheus

      expect(metrics).to include("turniere_action_cable_connections 1\n")
      expect(metrics).to include("turniere_action_cable_connections_total 2\n")
    end

    it 'does not let open websocket connections become negative' do
      described_class.action_cable_disconnected

      metrics = described_class.render_prometheus

      expect(metrics).to include("turniere_action_cable_connections 0\n")
    end
  end
end
