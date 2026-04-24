# frozen_string_literal: true

class TournamentMatchesPayload
  class << self
    def build(tournament, state: nil)
      serialized_matches(matches_for(tournament, state:))
    end

    def matches_for(tournament, state: nil)
      return tournament.matches if state.blank?
      return upcoming_matches_for(tournament) if state == 'upcoming'

      tournament.matches.select { |match| match.state == state }
    end

    private

    def upcoming_matches_for(tournament)
      upcoming_group_matches(tournament).presence || upcoming_playoff_matches(tournament)
    end

    def upcoming_group_matches(tournament)
      group_stage = tournament.stages.find { |stage| stage.level == -1 }
      return [] if group_stage.nil?

      group_stage.groups.filter_map do |group|
        group.matches.select { |match| match.state == 'not_started' }.min_by(&:position)
      end
    end

    def upcoming_playoff_matches(tournament)
      active_stage = playoff_stages(tournament).reverse.find do |stage|
        stage_with_running_matches?(stage)
      end
      return [] if active_stage.nil?

      tournament.stages.find { |stage| stage.level == active_stage.level - 1 }&.matches || []
    end

    def stage_with_running_matches?(stage)
      stage.matches.any? && stage.matches.all?(&:in_progress?)
    end

    def playoff_stages(tournament)
      tournament.stages.reject { |stage| stage.level.nil? }.sort_by(&:level)
    end

    def serialized_matches(matches)
      ActiveModelSerializers::SerializableResource.new(
        matches,
        each_serializer: LiveMatchSerializer,
        include: %w[match_scores.team]
      ).as_json
    end
  end
end
