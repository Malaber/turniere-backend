# frozen_string_literal: true

class TournamentMatchesPayload
  class << self
    def build(tournament, filters = {}, state: nil, **filter_keywords)
      serialized_matches(matches_for(tournament, filters.merge(filter_keywords), state:))
    end

    def matches_for(tournament, filters = {}, state: nil, **filter_keywords)
      filters = normalize_filters(filters.merge(filter_keywords), state:)
      matches = state_filtered_matches(tournament, filters[:state])

      matches.select { |match| match_matches_filters?(match, filters) }
    end

    def normalize_filters(filters = {}, state: nil)
      raw_filters = filters.to_h.with_indifferent_access
      raw_filters[:state] = state unless state.nil?

      {
        state: raw_filters[:state].presence,
        stage_id: integer_filter(raw_filters[:stage_id]),
        stage_level: integer_filter(raw_filters[:stage_level]),
        position: integer_filter(raw_filters[:position]),
        group_stage_position: integer_filter(raw_filters[:group_stage_position])
      }.compact
    end

    private

    def state_filtered_matches(tournament, state)
      return tournament.matches if state.blank?
      return upcoming_matches_for(tournament) if state == 'upcoming'

      tournament.matches.select { |match| match.state == state }
    end

    def match_matches_filters?(match, filters)
      stage = match_stage(match)

      stage_id_matches?(stage, filters) &&
        stage_level_matches?(stage, filters) &&
        position_matches?(match, filters) &&
        group_stage_position_matches?(match, stage, filters)
    end

    def match_stage(match)
      match.stage || match.group&.stage
    end

    def stage_id_matches?(stage, filters)
      filters[:stage_id].nil? || stage&.id == filters[:stage_id]
    end

    def stage_level_matches?(stage, filters)
      filters[:stage_level].nil? || stage&.level == filters[:stage_level]
    end

    def position_matches?(match, filters)
      filters[:position].nil? || match.position == filters[:position]
    end

    def group_stage_position_matches?(match, stage, filters)
      filters[:group_stage_position].nil? ||
        (match.group_match? && stage&.level == -1 && match.position == filters[:group_stage_position])
    end

    def integer_filter(value)
      return nil if value.blank?
      return value if value.is_a?(Integer)

      Integer(value, 10)
    rescue ArgumentError, TypeError
      :invalid
    end

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
