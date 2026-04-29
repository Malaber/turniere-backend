# frozen_string_literal: true

require 'json'
require 'time'

require_relative 'action_cable_client'
require_relative 'api_client'
require_relative 'scenario_runner'

module TurniereE2E
  class LoadTestRunner
    DEFAULT_HTTP_CLIENTS = [1, 10, 50, 100].freeze
    DEFAULT_WEBSOCKET_CLIENTS = [1, 10, 50, 100, 200].freeze

    def initialize(**options)
      @base_url = options.fetch(:base_url).delete_suffix('/')
      @email = options[:email]
      @password = options[:password]
      @username = options[:username]
      @tournament_id = options[:tournament_id]
      @http_clients = options.fetch(:http_clients, DEFAULT_HTTP_CLIENTS)
      @websocket_clients = options.fetch(:websocket_clients, DEFAULT_WEBSOCKET_CLIENTS)
      @http_requests_per_client = options.fetch(:http_requests_per_client, 3).to_i
      @websocket_hold_seconds = options.fetch(:websocket_hold_seconds, 1.0).to_f
      @websocket_connect_batch_size = options.fetch(:websocket_connect_batch_size, 25).to_i
      @group_count = options.fetch(:group_count, 4).to_i
      @teams_per_group = options.fetch(:teams_per_group, 4).to_i
      @playoff_teams_amount = options.fetch(:playoff_teams_amount, 8).to_i
      @fail_on_error = options.fetch(:fail_on_error, true)
    end

    def run
      tournament = prepare_tournament
      result = {
        base_url: base_url,
        tournament: tournament,
        http: http_clients.map { |client_count| run_http_level(tournament, client_count) },
        websocket: websocket_clients.map { |client_count| run_websocket_level(tournament, client_count) },
        metrics: metrics_summary
      }

      assert_success!(result) if fail_on_error
      result
    end

    private

    attr_reader :base_url, :email, :password, :username, :tournament_id, :http_clients, :websocket_clients,
                :http_requests_per_client, :websocket_hold_seconds, :websocket_connect_batch_size, :group_count,
                :teams_per_group, :playoff_teams_amount, :fail_on_error

    def prepare_tournament
      return fetch_existing_tournament if tournament_id.to_s.strip != ''

      runner = ScenarioRunner.new(base_url: base_url, email: email, password: password, username: username)
      runner.wait_for_healthcheck!
      result = runner.run_group_stage_render_profile(
        group_count: group_count,
        teams_per_group: teams_per_group,
        playoff_teams_amount: playoff_teams_amount,
        stop_at: :created
      )
      result.fetch(:tournament)
    end

    def fetch_existing_tournament
      client = ApiClient.new(base_url: base_url)
      response = client.get("/tournaments/#{tournament_id}")
      unless response.fetch(:status) == 200
        raise ApiError.new(
          "load-test tournament fetch failed with #{response.fetch(:status)}",
          status: response.fetch(:status),
          body: response.fetch(:json)
        )
      end

      summarize_tournament(response.fetch(:json))
    end

    def run_http_level(tournament, client_count)
      path = "/tournaments/#{tournament.fetch(:id)}"
      records = run_threads(client_count) do
        client = ApiClient.new(base_url: base_url)
        Array.new(http_requests_per_client) { measure_http_request(client, path) }
      end.flatten

      http_summary(client_count, records)
    end

    def run_websocket_level(tournament, client_count)
      clients = []
      baseline_connections = metric_scalar('turniere_action_cable_connections').to_i
      records = run_websocket_open_batches(tournament.fetch(:id), client_count, clients)
      successful = records.count { |record| record[:ok] }
      observed_connections = wait_for_connection_metric(successful)
      sleep websocket_hold_seconds if websocket_hold_seconds.positive?

      websocket_summary(client_count, records, baseline_connections, successful, observed_connections)
    ensure
      clients.each(&:close)
    end

    def run_websocket_open_batches(tournament_id, client_count, clients)
      batch_size = websocket_connect_batch_size.positive? ? websocket_connect_batch_size : client_count

      Array.new(client_count) { true }.each_slice(batch_size).flat_map do |batch|
        run_threads(batch.count) do
          measure_websocket_open(tournament_id).tap do |record|
            clients << record.delete(:client) if record[:client]
          end
        end
      end
    end

    def run_threads(count)
      return [] if count.to_i <= 0

      ready = Queue.new
      start = Queue.new
      results = Queue.new
      threads = Array.new(count) do
        Thread.new do
          ready << true
          start.pop
          results << yield
        rescue StandardError => e
          results << [{ error: "#{e.class}: #{e.message}" }]
        end
      end

      count.times { ready.pop }
      started_at = monotonic_time
      count.times { start << true }
      threads.each(&:join)
      finished_at = monotonic_time

      drain_queue(results).flatten.map do |record|
        record.is_a?(Hash) ? record.merge(level_duration_seconds: finished_at - started_at) : record
      end
    end

    def measure_http_request(client, path)
      started_at = monotonic_time
      response = client.get(path)
      {
        status: response.fetch(:status),
        duration_ms: elapsed_ms(started_at),
        body: error_body(response)
      }.compact
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}", duration_ms: elapsed_ms(started_at) }
    end

    def measure_websocket_open(tournament_id)
      client = ActionCableClient.new(base_url: base_url)
      started_at = monotonic_time
      client.subscribe_tournament!(tournament_id: tournament_id)
      payload = client.wait_for_tournament_payload!(timeout: 20)
      {
        ok: true,
        duration_ms: elapsed_ms(started_at),
        payload_type: payload.fetch('type'),
        client: client
      }
    rescue StandardError => e
      client&.close
      { ok: false, duration_ms: elapsed_ms(started_at), error: "#{e.class}: #{e.message}" }
    end

    def wait_for_connection_metric(expected, timeout: 10)
      deadline = monotonic_time + timeout
      loop do
        value = metric_scalar('turniere_action_cable_connections')
        return value if value && value >= expected
        return value if monotonic_time >= deadline

        sleep 0.2
      end
    end

    def metrics_summary
      {
        action_cable_connections: metric_scalar('turniere_action_cable_connections'),
        action_cable_connections_total: metric_scalar('turniere_action_cable_connections_total'),
        ruby_threads: metric_scalar('turniere_ruby_threads'),
        active_record_connections: metric_samples('turniere_active_record_connection_pool')
      }
    end

    def metric_scalar(name)
      metric_samples(name).map { |sample| sample.fetch(:value) }.max
    end

    def metric_samples(name)
      body = metrics_body
      body.lines.filter_map do |line|
        next if line.start_with?('#')

        sample, value = line.split(/\s+/, 2)
        next unless sample == name || sample.start_with?("#{name}{")

        { sample: sample, value: value.to_f }
      end
    end

    def metrics_body
      response = ApiClient.new(base_url: base_url).get('/metrics')
      return '' unless response.fetch(:status) == 200

      response.dig(:json, :raw_body).to_s
    end

    def assert_success!(result)
      failures = []
      result.fetch(:http).each { |level| failures.concat(http_failures(level)) }
      result.fetch(:websocket).each { |level| failures.concat(websocket_failures(level)) }

      raise "load test failed: #{failures.join('; ')}" unless failures.empty?
    end

    def http_summary(client_count, records)
      durations = records.filter_map { |record| record[:duration_ms] }
      errors = failed_http_records(records)

      {
        clients: client_count,
        requests: records.count,
        ok: records.count - errors.count,
        errors: errors.count,
        statuses: tally(records.filter_map { |record| record[:status] }),
        duration_ms: durations.sum.round(1),
        p50_ms: percentile(durations, 0.50),
        p95_ms: percentile(durations, 0.95),
        max_ms: durations.max&.round(1),
        requests_per_second: requests_per_second(records.count, records),
        error_samples: errors.first(3).map { |record| record.slice(:status, :error, :body) }
      }
    end

    def websocket_summary(client_count, records, baseline_connections, successful, observed_connections)
      durations = records.filter_map { |record| record[:duration_ms] }
      errors = records.reject { |record| record[:ok] }

      {
        clients: client_count,
        opened: successful,
        errors: errors.count,
        connection_metric: observed_connections,
        expected_connection_metric: successful,
        baseline_connection_metric: baseline_connections,
        p50_open_ms: percentile(durations, 0.50),
        p95_open_ms: percentile(durations, 0.95),
        max_open_ms: durations.max&.round(1),
        error_samples: errors.first(3).map { |record| record.slice(:error) }
      }
    end

    def failed_http_records(records)
      records.select { |record| record[:error] || record[:status].to_i >= 400 }
    end

    def http_failures(level)
      return [] unless level.fetch(:errors).positive?

      ["HTTP #{level.fetch(:clients)} clients: #{level.fetch(:errors)} failed"]
    end

    def websocket_failures(level)
      failures = []
      if level.fetch(:errors).positive?
        failures << "WS #{level.fetch(:clients)} clients: #{level.fetch(:errors)} failed"
      end
      if websocket_open_short?(level)
        failures << "WS #{level.fetch(:clients)} clients: only #{level.fetch(:opened)} opened"
      end
      if websocket_metric_short?(level)
        failures << "WS #{level.fetch(:clients)} clients: metrics saw #{level.fetch(:connection_metric)} connections"
      end
      failures
    end

    def websocket_open_short?(level)
      level.fetch(:opened) < level.fetch(:clients)
    end

    def websocket_metric_short?(level)
      level.fetch(:opened).positive? &&
        level.fetch(:connection_metric).to_i < level.fetch(:expected_connection_metric).to_i
    end

    def summarize_tournament(tournament)
      {
        id: tournament.fetch(:id),
        code: tournament.fetch(:code),
        playoff_teams_amount: tournament.fetch(:playoff_teams_amount),
        stage_count: tournament.fetch(:stages).count,
        team_count: tournament.fetch(:teams).count
      }
    end

    def error_body(response)
      return nil if response.fetch(:status).to_i < 400

      response.fetch(:json)
    end

    def requests_per_second(request_count, records)
      level_duration_seconds = records.filter_map { |record| record[:level_duration_seconds] }.max.to_f
      return nil unless level_duration_seconds.positive?

      (request_count / level_duration_seconds).round(2)
    end

    def percentile(values, quantile)
      sorted = values.compact.sort
      return nil if sorted.empty?

      index = [(sorted.length * quantile).ceil - 1, 0].max
      sorted.fetch(index).round(1)
    end

    def tally(values)
      values.each_with_object(Hash.new(0)) { |value, counts| counts[value.to_s] += 1 }
    end

    def drain_queue(queue)
      items = []
      items << queue.pop(true) until queue.empty?
      items
    rescue ThreadError
      items
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1000.0).round(1)
    end
  end
end
