#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'

require_relative 'lib/load_test_runner'

def parse_client_list(value)
  return [] if value.nil? || value.strip == '' || value.strip.casecmp('none').zero?

  value.split(',').map { |entry| Integer(entry.strip) }
end

options = {
  base_url: ENV.fetch('TURNIERE_E2E_BASE_URL', 'http://127.0.0.1:3000'),
  email: ENV['TURNIERE_E2E_EMAIL'],
  password: ENV['TURNIERE_E2E_PASSWORD'],
  username: ENV['TURNIERE_E2E_USERNAME'],
  tournament_id: ENV['TURNIERE_LOAD_TOURNAMENT_ID'],
  http_clients: parse_client_list(ENV.fetch('TURNIERE_LOAD_HTTP_CLIENTS', '1,10,50,100')),
  websocket_clients: parse_client_list(ENV.fetch('TURNIERE_LOAD_WEBSOCKET_CLIENTS', '1,10,50,100,200')),
  http_requests_per_client: Integer(ENV.fetch('TURNIERE_LOAD_HTTP_REQUESTS_PER_CLIENT', '3')),
  websocket_hold_seconds: Float(ENV.fetch('TURNIERE_LOAD_WEBSOCKET_HOLD_SECONDS', '1.0')),
  websocket_connect_batch_size: Integer(ENV.fetch('TURNIERE_LOAD_WEBSOCKET_CONNECT_BATCH_SIZE', '25')),
  group_count: Integer(ENV.fetch('TURNIERE_LOAD_GROUP_COUNT', '4')),
  teams_per_group: Integer(ENV.fetch('TURNIERE_LOAD_TEAMS_PER_GROUP', '4')),
  playoff_teams_amount: Integer(ENV.fetch('TURNIERE_LOAD_PLAYOFF_TEAMS', '8')),
  format: ENV.fetch('TURNIERE_LOAD_FORMAT', 'text')
}

# rubocop:disable Metrics/BlockLength
OptionParser.new do |parser|
  parser.banner = 'Usage: ruby e2e/load_test.rb [options]'

  parser.on('--base-url URL', 'API base URL') { |value| options[:base_url] = value }
  parser.on('--email EMAIL', 'Confirmed E2E user email') { |value| options[:email] = value }
  parser.on('--password PASSWORD', 'Confirmed E2E user password') { |value| options[:password] = value }
  parser.on('--username USERNAME', 'Confirmed E2E user username') { |value| options[:username] = value }
  parser.on('--tournament-id ID', 'Existing tournament ID instead of creating one') do |value|
    options[:tournament_id] = value
  end
  parser.on('--http-clients LIST', 'Comma-separated HTTP client levels, or none') do |value|
    options[:http_clients] = parse_client_list(value)
  end
  parser.on('--websocket-clients LIST', 'Comma-separated websocket client levels, or none') do |value|
    options[:websocket_clients] = parse_client_list(value)
  end
  parser.on('--http-requests-per-client COUNT', Integer, 'GET requests per HTTP client') do |value|
    options[:http_requests_per_client] = value
  end
  parser.on('--websocket-hold-seconds SECONDS', Float, 'Seconds to hold websocket clients open') do |value|
    options[:websocket_hold_seconds] = value
  end
  parser.on('--websocket-connect-batch-size COUNT', Integer, 'Concurrent websocket handshakes per batch') do |value|
    options[:websocket_connect_batch_size] = value
  end
  parser.on('--group-count COUNT', Integer, 'Groups in generated tournament') { |value| options[:group_count] = value }
  parser.on('--teams-per-group COUNT', Integer, 'Teams per generated group') do |value|
    options[:teams_per_group] = value
  end
  parser.on('--playoff-teams-amount COUNT', Integer, 'Playoff teams in generated tournament') do |value|
    options[:playoff_teams_amount] = value
  end
  parser.on('--format FORMAT', 'text or json') { |value| options[:format] = value }
end.parse!
# rubocop:enable Metrics/BlockLength

runner_options = options.dup
runner_options.delete(:format)
runner = TurniereE2E::LoadTestRunner.new(**runner_options)
result = runner.run

if options[:format] == 'json'
  puts JSON.pretty_generate(result)
  exit
end

puts "Load test base_url=#{result.fetch(:base_url)} tournament_id=#{result.dig(:tournament, :id)}"

result.fetch(:http).each do |level|
  puts(
    "HTTP #{level.fetch(:clients)} clients: " \
    "#{level.fetch(:ok)}/#{level.fetch(:requests)} ok, errors=#{level.fetch(:errors)}, " \
    "p50=#{level.fetch(:p50_ms)}ms, p95=#{level.fetch(:p95_ms)}ms, " \
    "max=#{level.fetch(:max_ms)}ms, rps=#{level.fetch(:requests_per_second)}"
  )
end

result.fetch(:websocket).each do |level|
  puts(
    "WS #{level.fetch(:clients)} clients: " \
    "opened=#{level.fetch(:opened)}, errors=#{level.fetch(:errors)}, " \
    "p50_open=#{level.fetch(:p50_open_ms)}ms, p95_open=#{level.fetch(:p95_open_ms)}ms, " \
    "connections_metric=#{level.fetch(:connection_metric)}"
  )
end

metrics = result.fetch(:metrics)
puts(
  "Metrics: action_cable_connections=#{metrics.fetch(:action_cable_connections)}, " \
  "action_cable_connections_total=#{metrics.fetch(:action_cable_connections_total)}, " \
  "ruby_threads=#{metrics.fetch(:ruby_threads)}"
)
