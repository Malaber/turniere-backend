# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

class TournamentSyncPusher
  class SyncFailed < StandardError; end
  DEFAULT_HTTP_TIMEOUT = 5

  def self.push!(tournament)
    new(tournament).push!
  end

  def self.push_snapshot!(tournament, snapshot)
    new(tournament).push_snapshot!(snapshot)
  end

  def initialize(tournament)
    @tournament = tournament
  end

  def push!
    return false unless tournament.sync_push_enabled?

    push_snapshot!(TournamentSnapshotBuilder.build(tournament))
  end

  def push_snapshot!(snapshot)
    response = perform_request(snapshot: snapshot)

    unless response.is_a?(Net::HTTPSuccess)
      raise SyncFailed, "sync push failed with status #{response.code}: #{response.body}"
    end

    tournament.update_columns(sync_last_pushed_at: Time.current, sync_last_push_error: nil)
    true
  rescue SyncFailed => e
    tournament.update_columns(sync_last_push_error: e.message)
    raise
  rescue StandardError => e
    tournament.update_columns(sync_last_push_error: e.message)
    raise SyncFailed, e.message
  end

  private

  attr_reader :tournament

  def perform_request(snapshot:)
    uri = URI.parse(tournament.sync_target_url)
    request = Net::HTTP::Patch.new(uri)
    request['accept'] = 'application/json'
    request['content-type'] = 'application/json'
    request['authorization'] = "Bearer #{tournament.sync_auth_token}"
    request.body = JSON.dump({ snapshot: snapshot })

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      timeout = http_timeout_seconds
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout if http.respond_to?(:write_timeout=)
      http.request(request)
    end
  end

  def http_timeout_seconds
    ENV.fetch('TOURNAMENT_SYNC_HTTP_TIMEOUT_SECONDS', DEFAULT_HTTP_TIMEOUT).to_i
  end
end
