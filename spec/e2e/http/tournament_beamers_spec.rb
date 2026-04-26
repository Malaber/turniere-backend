# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require_relative '../../../e2e/lib/api_client'

RSpec.describe 'Tournament beamer HTTP E2E' do
  required_env_vars = %w[
    TURNIERE_E2E_BASE_URL
    TURNIERE_E2E_EMAIL
    TURNIERE_E2E_PASSWORD
    TURNIERE_E2E_ALT_EMAIL
    TURNIERE_E2E_ALT_PASSWORD
  ].freeze

  before do
    missing_vars = required_env_vars.reject { |name| ENV.key?(name) }
    skip("HTTP E2E requires #{missing_vars.join(', ')}") unless missing_vars.empty?
  end

  let(:base_url) { ENV.fetch('TURNIERE_E2E_BASE_URL') }
  let(:owner_email) { ENV.fetch('TURNIERE_E2E_EMAIL') }
  let(:owner_password) { ENV.fetch('TURNIERE_E2E_PASSWORD') }
  let(:other_email) { ENV.fetch('TURNIERE_E2E_ALT_EMAIL') }
  let(:other_password) { ENV.fetch('TURNIERE_E2E_ALT_PASSWORD') }
  let(:owner_client) { login_client(email: owner_email, password: owner_password) }
  let(:other_client) { login_client(email: other_email, password: other_password) }
  let(:anonymous_client) { TurniereE2E::ApiClient.new(base_url:) }

  it 'exercises beamer control endpoints over HTTP' do
    tournament = create_tournament(client: owner_client, name_prefix: 'Beamer Control')

    default_beamer = anonymous_client.get(
      beamer_by_name_path(tournament.fetch(:id)),
      params: { name: 'missing' }
    )
    default_show = anonymous_client.get(beamer_path(tournament.fetch(:id), default_beamer.dig(:json, :id)))

    expect(default_beamer[:status]).to eq(200)
    expect(default_beamer.dig(:json, :name)).to eq('default')
    expect(default_beamer.dig(:json, :display_state)).to eq('matches_all')
    expect(default_show[:status]).to eq(200)

    create_response = owner_client.post("/tournaments/#{tournament.fetch(:id)}/beamers", body: {
                                          name: 'hall-a',
                                          display_state: 'groups',
                                          qr_code_url: 'https://example.com/hall-a',
                                          logo_url: '/logos/hall-a.png'
                                        })
    expect(create_response[:status]).to eq(201)
    beamer = create_response.fetch(:json)
    expect(beamer.fetch(:name)).to eq('hall-a')
    expect(beamer.fetch(:display_state)).to eq('groups')
    expect(beamer.fetch(:qr_code_url)).to eq('https://example.com/hall-a')

    index_response = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}/beamers")
    show_response = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}/beamers/#{beamer.fetch(:id)}")
    by_name_response = anonymous_client.get(beamer_by_name_path(tournament.fetch(:id)), params: { name: 'hall-a' })

    expect(index_response[:status]).to eq(200)
    expect(index_response.fetch(:json).map { |item| item.fetch(:name) }).to contain_exactly('default', 'hall-a')
    expect(show_response[:status]).to eq(200)
    expect(show_response.dig(:json, :id)).to eq(beamer.fetch(:id))
    expect(by_name_response[:status]).to eq(200)
    expect(by_name_response.dig(:json, :id)).to eq(beamer.fetch(:id))

    update_response = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/beamers/#{beamer.fetch(:id)}", body: {
                                           display_state: 'during_game',
                                           qr_code_url: 'https://example.com/live',
                                           logo_url: '/logos/live.png'
                                         })
    expect(update_response[:status]).to eq(200)
    expect(update_response.dig(:json, :display_state)).to eq('during_game')
    expect(update_response.dig(:json, :qr_code_url)).to eq('https://example.com/live')
    expect(update_response.dig(:json, :logo_url)).to eq('/logos/live.png')

    invalid_update = owner_client.patch("/tournaments/#{tournament.fetch(:id)}/beamers/#{beamer.fetch(:id)}", body: {
                                          display_state: 'bogus'
                                        })
    duplicate_create = owner_client.post("/tournaments/#{tournament.fetch(:id)}/beamers", body: {
                                           name: 'hall-a',
                                           display_state: 'matches_all'
                                         })
    forbidden_update = other_client.patch("/tournaments/#{tournament.fetch(:id)}/beamers/#{beamer.fetch(:id)}", body: {
                                            display_state: 'groups'
                                          })
    unauthenticated_create = anonymous_client.post(
      "/tournaments/#{tournament.fetch(:id)}/beamers",
      body: {
        name: 'anon',
        display_state: 'groups'
      }
    )

    expect(invalid_update[:status]).to eq(422)
    expect(duplicate_create[:status]).to eq(422)
    expect(forbidden_update[:status]).to eq(403)
    expect(unauthenticated_create[:status]).to eq(401)

    read_only_tournament = create_tournament(
      client: owner_client,
      name_prefix: 'Beamer Read Only',
      read_only_mode: true
    )
    read_only_beamer = anonymous_client.get(
      beamer_by_name_path(read_only_tournament.fetch(:id)),
      params: { name: 'default' }
    )
    locked_update = owner_client.patch(
      beamer_path(read_only_tournament.fetch(:id), read_only_beamer.dig(:json, :id)),
      body: { display_state: 'groups' }
    )
    expect(locked_update[:status]).to eq(423)

    delete_response = owner_client.delete("/tournaments/#{tournament.fetch(:id)}/beamers/#{beamer.fetch(:id)}")
    deleted_show = anonymous_client.get("/tournaments/#{tournament.fetch(:id)}/beamers/#{beamer.fetch(:id)}")
    deleted_by_name = anonymous_client.get(beamer_by_name_path(tournament.fetch(:id)), params: { name: 'hall-a' })

    expect(delete_response[:status]).to eq(204)
    expect(deleted_show[:status]).to eq(404)
    expect(deleted_by_name[:status]).to eq(200)
    expect(deleted_by_name.dig(:json, :name)).to eq('default')
  end

  def login_client(email:, password:)
    api_client = TurniereE2E::ApiClient.new(base_url:)
    response = api_client.login!(email:, password:)

    expect(response[:status]).to eq(200)
    api_client
  end

  def create_tournament(client:, name_prefix:, read_only_mode: false)
    response = client.post('/tournaments', body: {
                             name: "#{name_prefix} #{SecureRandom.hex(3)}",
                             description: 'HTTP beamer control tournament',
                             public: true,
                             read_only_mode:,
                             teams: Array.new(4) do |index|
                               { name: "#{name_prefix.tr(' ', '')}-S#{index + 1}" }
                             end
                           })
    expect(response[:status]).to eq(201)
    response.fetch(:json)
  end

  def beamer_path(tournament_id, beamer_id)
    "/tournaments/#{tournament_id}/beamers/#{beamer_id}"
  end

  def beamer_by_name_path(tournament_id)
    "/tournaments/#{tournament_id}/beamers/by_name"
  end
end
