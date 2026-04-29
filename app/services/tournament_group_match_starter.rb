# frozen_string_literal: true

class TournamentGroupMatchStarter
  class << self
    def upcoming_matches(tournament)
      group_stage = tournament.group_stage
      return [] if group_stage.nil?

      next_matches = group_stage.groups.filter_map do |group|
        group.matches.not_started.order(:position).first
      end
      lowest_position = next_matches.map(&:position).min
      return [] if lowest_position.nil?

      next_matches.select { |match| match.position == lowest_position }
                  .sort_by { |match| [match.position, match.group.number, match.id] }
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

    def recalculate_group_scores!(matches, logger:)
      matches.map(&:group).uniq.each do |group|
        next if UpdateGroupsGroupScoresAndSave.call(group:).success?

        logger.warn "Updating groups group score failed for #{group}"
      end
    end
  end
end
