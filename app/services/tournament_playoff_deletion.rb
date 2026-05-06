# frozen_string_literal: true

class TournamentPlayoffDeletion
  DELETABLE_MATCH_STATES = %w[not_started not_ready single_team].freeze

  Result = Struct.new(:success, :error, keyword_init: true) do
    def success?
      success
    end
  end

  def self.call(tournament:)
    new(tournament).call
  end

  def initialize(tournament)
    @tournament = tournament
  end

  def call
    group_stage = tournament.group_stage
    return failure('Only group-stage playoffs can be deleted') if group_stage.nil?

    playoff_stages = tournament.stages.reload.select { |stage| stage.level >= 0 }
    return failure('Playoffs have not been generated') if playoff_stages.empty?
    return failure('Playoffs cannot be deleted after matches have started or scores changed') unless playoffs_deletable?(playoff_stages)

    playoff_stages.each(&:destroy!)
    group_stage.update!(state: :in_progress)
    success
  end

  private

  attr_reader :tournament

  def playoffs_deletable?(playoff_stages)
    playoff_stages.flat_map(&:matches).all? do |match|
      DELETABLE_MATCH_STATES.include?(match.state) && zero_scores?(match)
    end
  end

  def zero_scores?(match)
    match.match_scores.all? do |score|
      score.points.to_i.zero? && score.hidden_points.to_i.zero?
    end
  end

  def success
    Result.new(success: true)
  end

  def failure(error)
    Result.new(success: false, error: error)
  end
end
