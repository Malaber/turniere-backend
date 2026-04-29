# frozen_string_literal: true

class TournamentGroupMatchStarter
  class << self
    def upcoming_matches(tournament)
      group_matches = not_started_group_matches(tournament)
      lowest_position = group_matches.minimum(:position)
      return [] if lowest_position.nil?

      selected_lowest_matches(group_matches, lowest_position)
    end

    def start_next!(tournament, logger: Rails.logger)
      started_matches = []

      Match.transaction do
        started_matches = upcoming_matches(tournament)
        started_matches.each { |match| match.update!(state: :in_progress) }
        recalculate_group_scores!(started_matches, logger:)
      end

      started_matches
    end

    private

    def not_started_group_matches(tournament)
      group_stage = tournament.group_stage
      return Match.none if group_stage.nil?

      group_ids = group_stage.groups.ids
      return Match.none if group_ids.empty?

      Match.where(group_id: group_ids).not_started
    end

    def selected_lowest_matches(group_matches, lowest_position)
      group_matches.where(position: lowest_position)
                   .includes(:group)
                   .group_by(&:group_id)
                   .values
                   .map { |matches| matches.min_by(&:id) }
                   .sort_by { |match| [match.position, match.group.number, match.id] }
    end

    def recalculate_group_scores!(matches, logger:)
      matches.map(&:group).uniq.each do |group|
        next if UpdateGroupsGroupScoresAndSave.call(group:).success?

        logger.warn "Updating groups group score failed for #{group}"
      end
    end
  end
end
