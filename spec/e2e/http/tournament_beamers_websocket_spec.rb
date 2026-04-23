# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'
require_relative '../../../e2e/lib/action_cable_client'

RSpec.describe 'Tournament beamer websocket HTTP E2E' do
  required_env_vars = %w[
    TURNIERE_E2E_BASE_URL
    TURNIERE_E2E_EMAIL
    TURNIERE_E2E_PASSWORD
  ].freeze

  before do
    missing_vars = required_env_vars.reject { |name| ENV.key?(name) }
    skip("HTTP E2E requires #{missing_vars.join(', ')}") unless missing_vars.empty?
  end

  let(:base_url) { ENV.fetch('TURNIERE_E2E_BASE_URL') }
  let(:owner_email) { ENV.fetch('TURNIERE_E2E_EMAIL') }
  let(:owner_password) { ENV.fetch('TURNIERE_E2E_PASSWORD') }
  let(:client) { login_client }

  it 'broadcasts beamer snapshots and updates over websocket' do
    tournament = create_tournament(name_prefix: 'Ws Beamer')
    create_beamer = client.post("/tournaments/#{tournament.fetch(:id)}/beamers", body: {
                                  name: 'projector-a',
                                  display_state: 'matches_all'
                                })
    expect(create_beamer[:status]).to eq(201)
    beamer = create_beamer.fetch(:json)

    cable_client = TurniereE2E::ActionCableClient.new(base_url:)
    cable_client.subscribe_beamer!(tournament_id: tournament.fetch(:id), beamer_name: beamer.fetch(:name))

    initial_payload = cable_client.wait_for_beamer_payload!
    expect(initial_payload.fetch('type')).to eq('beamer.snapshot')
    expect(initial_payload.dig('beamer', 'id')).to eq(beamer.fetch(:id))
    expect(initial_payload.dig('beamer', 'display_state')).to eq('matches_all')

    update = client.patch("/tournaments/#{tournament.fetch(:id)}/beamers/#{beamer.fetch(:id)}", body: {
                            display_state: 'during_game',
                            qr_code_url: 'https://example.com/qr',
                            logo_url: '/static/logo.png'
                          })
    expect(update[:status]).to eq(200)

    updated_payload = wait_for_beamer_payload!(
      cable_client,
      event_type: 'beamer.updated',
      display_state: 'during_game'
    )
    expect(updated_payload.dig('beamer', 'qr_code_url')).to eq('https://example.com/qr')
    expect(updated_payload.dig('beamer', 'logo_url')).to eq('/static/logo.png')

    delete = client.delete("/tournaments/#{tournament.fetch(:id)}/beamers/#{beamer.fetch(:id)}")
    expect(delete[:status]).to eq(204)

    deleted_payload = wait_for_beamer_payload!(
      cable_client,
      event_type: 'beamer.deleted',
      display_state: 'during_game'
    )
    expect(deleted_payload.dig('beamer', 'name')).to eq('projector-a')
  ensure
    cable_client&.close
  end

  def login_client
    api_client = TurniereE2E::ApiClient.new(base_url:)
    response = api_client.login!(email: owner_email, password: owner_password)

    expect(response[:status]).to eq(200)
    api_client
  end

  def create_tournament(name_prefix:)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'Websocket beamer tournament',
                             public: true
                           })
    expect(response[:status]).to eq(201)
    response.fetch(:json)
  end

  def wait_for_beamer_payload!(cable_client, event_type:, display_state:, timeout: 20)
    deadline = Time.now + timeout
    loop do
      payload = cable_client.wait_for_beamer_payload!(timeout: [deadline - Time.now, 0.1].max)
      return payload if payload.fetch('type') == event_type &&
                        payload.dig('beamer', 'display_state') == display_state

      raise "beamer websocket payload not received within #{timeout}s" if Time.now >= deadline
    end
  end
end
