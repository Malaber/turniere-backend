#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative '../e2e/lib/scenario_runner'

def write_line(message)
  $stdout.write("#{message}\n")
end

def fail_with(message)
  $stderr.write("#{message}\n")
  raise SystemExit, 1
end

options = {
  base_url: ENV.fetch('TURNIERE_E2E_BASE_URL', 'http://127.0.0.1:3000'),
  stop_at: nil,
  team_count: 8,
  group_count: 4,
  teams_per_group: 4,
  playoff_teams_amount: 8,
  email: ENV.fetch('TURNIERE_E2E_EMAIL', nil),
  password: ENV.fetch('TURNIERE_E2E_PASSWORD', nil),
  username: ENV.fetch('TURNIERE_E2E_USERNAME', nil)
}

OptionParser.new do |parser|
  parser.banner = 'Usage: script/e2e_scenarios.rb SCENARIO [options]'

  parser.on('--base-url URL', 'API base URL') { |value| options[:base_url] = value }
  parser.on('--stop-at CHECKPOINT', 'Stop scenario at a named checkpoint') { |value| options[:stop_at] = value.to_sym }
  parser.on('--team-count COUNT', Integer, 'Team count for playoff_only scenario') do |value|
    options[:team_count] = value
  end
  parser.on('--group-count COUNT', Integer, 'Group count for group-stage scenarios') do |value|
    options[:group_count] = value
  end
  parser.on('--teams-per-group COUNT', Integer, 'Teams per group for group-stage scenarios') do |value|
    options[:teams_per_group] = value
  end
  parser.on('--playoff-teams-amount COUNT', Integer, 'Playoff teams amount for group-stage scenarios') do |value|
    options[:playoff_teams_amount] = value
  end
  parser.on('--email EMAIL', 'Confirmed E2E user email') { |value| options[:email] = value }
  parser.on('--password PASSWORD', 'Confirmed E2E user password') { |value| options[:password] = value }
  parser.on('--username USERNAME', 'Confirmed E2E user username') { |value| options[:username] = value }
end.parse!

scenario = ARGV.shift
fail_with('Missing scenario name') if scenario.nil?

runner = TurniereE2E::ScenarioRunner.new(
  base_url: options[:base_url],
  email: options[:email],
  password: options[:password],
  username: options[:username]
)

result = case scenario
         when 'group_stage_main_usecase'
           runner.run_group_stage_main_usecase(stop_at: options[:stop_at] || :final_finish_attempted)
         when 'group_stage_intermediate_round'
           runner.run_group_stage_intermediate_round(stop_at: options[:stop_at] || :final_finish_attempted)
         when 'group_stage_playoff_recreation'
           runner.run_group_stage_playoff_recreation(stop_at: options[:stop_at] || :third_playoffs_created)
         when 'playoff_only'
           runner.run_playoff_only(team_count: options[:team_count], stop_at: options[:stop_at] || :completed)
         when 'group_stage_render_profile'
           runner.run_group_stage_render_profile(
             group_count: options[:group_count],
             teams_per_group: options[:teams_per_group],
             playoff_teams_amount: options[:playoff_teams_amount],
             stop_at: options[:stop_at] || :profiled_show
           )
         else
           fail_with("Unknown scenario #{scenario.inspect}")
         end

write_line JSON.pretty_generate(result)
