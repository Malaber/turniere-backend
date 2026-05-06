#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../e2e/lib/scenario_runner'

url = ARGV[0] || ENV.fetch('TURNIERE_E2E_BASE_URL', 'http://127.0.0.1:3000')
timeout = (ARGV[1] || 30).to_i

runner = TurniereE2E::ScenarioRunner.new(base_url: url)
runner.wait_for_healthcheck!(timeout_seconds: timeout)
$stdout.write("ready: #{url}\n")
