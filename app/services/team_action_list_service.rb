# frozen_string_literal: true

class TeamActionListService
  SUPPORTED_SOURCES = %w[all_tournament_teams group_stage_survivors].freeze

  class InvalidSourceError < StandardError; end
  class EmptySourceError < StandardError; end

  class << self
    def create!(tournament:, name:, key:, action_name:, source:)
      teams = teams_for_source!(tournament:, source:)
      raise EmptySourceError, "Source #{source} does not currently contain any teams" if teams.empty?

      list = nil
      TeamActionList.transaction do
        list = tournament.team_action_lists.new(
          name:,
          key:,
          action_name:,
          source:
        )
        list.save!
        list.sync_teams!(teams)
      end

      TournamentSyncEnqueue.call(tournament)
      list
    end

    def source_keys
      SUPPORTED_SOURCES
    end

    def teams_for_source!(tournament:, source:)
      case source
      when 'all_tournament_teams'
        tournament.teams.to_a
      when 'group_stage_survivors'
        group_stage = tournament.group_stage
        return [] unless group_stage&.finished?

        tournament.teams_advancing_from_group_stage
      else
        raise InvalidSourceError, "Unsupported team action list source: #{source}"
      end
    end
  end
end
