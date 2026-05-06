# frozen_string_literal: true

class AccountProfileSerializer < AccountSummarySerializer
  attributes :tournaments, :created_tournaments, :teams

  def tournaments
    visible_played_tournaments.map { |tournament| tournament_summary(tournament) }
  end

  def created_tournaments
    visible_created_tournaments.map { |tournament| tournament_summary(tournament) }
  end

  def teams
    visible_player_teams.map do |team|
      {
        id: team.id,
        name: team.name,
        tournament: tournament_summary(team.tournament)
      }
    end
  end

  private

  def visible_played_tournaments
    visible_tournaments(object.played_tournaments.order(:created_at))
  end

  def visible_created_tournaments
    visible_tournaments(object.tournaments.order(:created_at))
  end

  def visible_player_teams
    object.player_teams.includes(:tournament).order(:created_at).select do |team|
      profile_owner? || team.tournament&.public?
    end
  end

  def visible_tournaments(scope)
    return scope if profile_owner?

    scope.where(public: true)
  end

  def profile_owner?
    scope == object
  end

  def tournament_summary(tournament)
    return nil if tournament.nil?

    {
      id: tournament.id,
      name: tournament.name,
      code: tournament.code,
      public: tournament.public
    }
  end
end
