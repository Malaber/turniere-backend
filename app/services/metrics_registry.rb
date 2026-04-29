# frozen_string_literal: true

class MetricsRegistry
  HTTP_LABELS = %i[method controller action status].freeze
  REQUEST_DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze
  STARTED_AT = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  class << self
    def record_http_request(method:, controller:, action:, status:, duration:)
      labels = http_labels(method:, controller:, action:, status:)

      synchronize do
        @http_requests[labels] += 1
        histogram = @http_request_duration[labels]
        histogram[:count] += 1
        histogram[:sum] += duration.to_f
        REQUEST_DURATION_BUCKETS.each do |bucket|
          histogram[:buckets][bucket] += 1 if duration.to_f <= bucket
        end
      end
    end

    def action_cable_connected
      synchronize do
        @action_cable_connections += 1
        @action_cable_connections_total += 1
      end
    end

    def action_cable_disconnected
      synchronize do
        @action_cable_connections = [@action_cable_connections - 1, 0].max
      end
    end

    def render_prometheus
      snapshot = snapshot_metrics

      PrometheusRenderer.new(snapshot).render
    end

    def reset!
      @mutex = Mutex.new
      @http_requests = Hash.new(0)
      @http_request_duration = Hash.new do |hash, labels|
        hash[labels] = {
          count: 0,
          sum: 0.0,
          buckets: REQUEST_DURATION_BUCKETS.index_with(0)
        }
      end
      @action_cable_connections = 0
      @action_cable_connections_total = 0
    end

    private

    def synchronize(&block)
      reset! if @mutex.nil?

      @mutex.synchronize(&block)
    end

    def snapshot_metrics
      synchronize do
        {
          http_requests: @http_requests.dup,
          http_request_duration: @http_request_duration.transform_values do |histogram|
            {
              count: histogram.fetch(:count),
              sum: histogram.fetch(:sum),
              buckets: histogram.fetch(:buckets).dup
            }
          end,
          action_cable_connections: @action_cable_connections,
          action_cable_connections_total: @action_cable_connections_total,
          uptime_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - STARTED_AT,
          active_record_pool: active_record_pool_stats,
          git_commit_sha: ENV.fetch('GIT_COMMIT_SHA', 'unknown')
        }
      end
    end

    def http_labels(method:, controller:, action:, status:)
      {
        method: method.to_s.upcase,
        controller: controller.to_s,
        action: action.to_s,
        status: status.to_i.to_s
      }.freeze
    end

    def active_record_pool_stats
      return {} unless defined?(ActiveRecord::Base)

      ActiveRecord::Base.connection_pool.stat
    rescue StandardError
      {}
    end
  end

  class PrometheusRenderer
    def initialize(snapshot)
      @snapshot = snapshot
      @lines = []
    end

    def render
      render_build_info
      render_http_requests
      render_http_request_duration
      render_action_cable_connections
      render_process_metrics
      render_active_record_pool

      "#{lines.join("\n")}\n"
    end

    private

    attr_reader :snapshot, :lines

    def render_build_info
      help('turniere_build_info', 'Build metadata for this process.')
      type('turniere_build_info', 'gauge')
      sample('turniere_build_info', 1, git_commit_sha: snapshot.fetch(:git_commit_sha))
    end

    def render_http_requests
      help('turniere_http_requests_total', 'Total HTTP requests handled by Rails controllers.')
      type('turniere_http_requests_total', 'counter')
      snapshot.fetch(:http_requests).each do |labels, count|
        sample('turniere_http_requests_total', count, labels)
      end
    end

    def render_http_request_duration
      help('turniere_http_request_duration_seconds', 'HTTP request duration in seconds.')
      type('turniere_http_request_duration_seconds', 'histogram')
      snapshot.fetch(:http_request_duration).each do |labels, histogram|
        histogram.fetch(:buckets).each do |bucket, count|
          sample('turniere_http_request_duration_seconds_bucket', count, labels.merge(le: format_number(bucket)))
        end
        sample('turniere_http_request_duration_seconds_bucket', histogram.fetch(:count), labels.merge(le: '+Inf'))
        sample('turniere_http_request_duration_seconds_sum', histogram.fetch(:sum), labels)
        sample('turniere_http_request_duration_seconds_count', histogram.fetch(:count), labels)
      end
    end

    def render_action_cable_connections
      help('turniere_action_cable_connections', 'Currently open ActionCable websocket connections.')
      type('turniere_action_cable_connections', 'gauge')
      sample('turniere_action_cable_connections', snapshot.fetch(:action_cable_connections))

      help('turniere_action_cable_connections_total', 'Total ActionCable websocket connections opened.')
      type('turniere_action_cable_connections_total', 'counter')
      sample('turniere_action_cable_connections_total', snapshot.fetch(:action_cable_connections_total))
    end

    def render_process_metrics
      help('turniere_process_uptime_seconds', 'Process uptime in seconds.')
      type('turniere_process_uptime_seconds', 'gauge')
      sample('turniere_process_uptime_seconds', snapshot.fetch(:uptime_seconds))

      help('turniere_ruby_threads', 'Ruby threads visible in this process.')
      type('turniere_ruby_threads', 'gauge')
      sample('turniere_ruby_threads', Thread.list.count)
    end

    def render_active_record_pool
      help('turniere_active_record_connection_pool', 'ActiveRecord connection pool state.')
      type('turniere_active_record_connection_pool', 'gauge')
      snapshot.fetch(:active_record_pool).each do |state, value|
        sample('turniere_active_record_connection_pool', value, state:)
      end
    end

    def help(name, text)
      lines << "# HELP #{name} #{text}"
    end

    def type(name, type)
      lines << "# TYPE #{name} #{type}"
    end

    def sample(name, value, labels = {})
      lines << "#{name}#{labels_string(labels)} #{format_number(value)}"
    end

    def labels_string(labels)
      return '' if labels.empty?

      formatted = labels.map do |key, value|
        %(#{key}="#{escape_label_value(value)}")
      end

      "{#{formatted.join(',')}}"
    end

    def escape_label_value(value)
      value.to_s.gsub('\\', '\\\\\\').gsub("\n", '\\n').gsub('"', '\"')
    end

    def format_number(value)
      return value.to_s if value.is_a?(Integer)

      format('%.12g', value)
    end
  end
end

MetricsRegistry.reset!
