# frozen_string_literal: true

module PerformanceHelpers
  IGNORED_SQL_NAMES = %w[SCHEMA CACHE].freeze
  IGNORED_SQL = /\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i

  def capture_runtime_and_queries
    query_count = 0
    subscriber = lambda do |_name, _start, _finish, _id, payload|
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

    duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0
    { result: result, query_count: query_count, duration_ms: duration_ms }
  end

  def create_group_stage_tournament(groups_count:, teams_per_group:)
    owner = create(:user)
    tournament = owner.tournaments.create!(
      name: "Perf #{groups_count}x#{teams_per_group}",
      description: 'Tournament render performance fixture',
      public: true,
      playoff_teams_amount: groups_count
    )

    groups = Array.new(groups_count) do |group_index|
      Array.new(teams_per_group) do |team_index|
        tournament.teams.create!(name: "G#{group_index + 1}-T#{team_index + 1}")
      end
    end

    group_stage = GroupStageService.generate_group_stage(groups)
    tournament.stages = [group_stage]
    tournament.instant_finalists_amount, tournament.intermediate_round_participants_amount =
      TournamentService.calculate_default_amount_of_teams_advancing(tournament.playoff_teams_amount, groups_count)
    tournament.save!

    tournament.reload
  end
end

RSpec.configure do |config|
  config.include PerformanceHelpers
end
