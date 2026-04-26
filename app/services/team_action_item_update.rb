# frozen_string_literal: true

class TeamActionItemUpdate
  class << self
    def call(team_action_item:, completed:)
      new(team_action_item:, completed:).call
    end
  end

  def initialize(team_action_item:, completed:)
    @team_action_item = team_action_item
    @completed = completed
  end

  def call
    return false unless team_action_item.update(completed:)

    TournamentSyncEnqueue.call(team_action_item.tournament)
    true
  end

  private

  attr_reader :team_action_item, :completed
end
