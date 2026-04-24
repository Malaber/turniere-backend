# frozen_string_literal: true

class TournamentMatchesPayload
  class << self
    def build(tournament, state: nil)
      serialized_matches(matches_for(tournament, state: state))
    end

    def matches_for(tournament, state: nil)
      return tournament.matches if state.blank?
      return upcoming_matches_for(tournament) if state == 'upcoming'

      tournament.matches.select { |match| match.state == state }
    end

    private

    def upcoming_matches_for(tournament)
      group_stage = tournament.stages.find { |stage| stage.level == -1 }
      group_matches = group_stage&.groups&.map do |group|
        group.matches.select { |match| match.state == 'not_started' }.min_by(&:position)
      end&.compact
      return group_matches unless group_matches.blank?

      next_level = nil
      tournament.stages.reject { |stage| stage.level.nil? }.sort_by(&:level).reverse_each do |stage|
        next unless stage.matches.any?
        next unless stage.matches.all?(&:in_progress?)

        next_level = stage.level - 1
        break
      end

      tournament.stages.find { |stage| stage.level == next_level }&.matches || []
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
