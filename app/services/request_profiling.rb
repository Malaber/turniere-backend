# frozen_string_literal: true

class RequestProfiling
  IGNORED_SQL_NAMES = %w[SCHEMA CACHE].freeze
  IGNORED_SQL = /\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i

  def initialize(enabled: false)
    @enabled = enabled
    @measurements = []
  end

  def measure(name)
    return yield unless @enabled

    query_count = 0
    subscriber = lambda do |_event_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if IGNORED_SQL_NAMES.include?(payload[:name])
      next if sql.match?(IGNORED_SQL)

      query_count += 1
    end

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = nil
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      result = yield
    end
    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0
    @measurements << { name: name, duration: duration.round(1), query_count: query_count }
    result
  end

  def apply_to(response, label:)
    return unless @enabled

    response.set_header('Server-Timing', @measurements.map { |m| "#{m[:name]};dur=#{m[:duration]}" }.join(', '))
    response.set_header(
      'X-Turniere-Profile',
      "#{label}: #{@measurements.map { |m| "#{m[:name]}=#{m[:duration]}ms/#{m[:query_count]}sql" }.join(', ')}"
    )
  end
end
