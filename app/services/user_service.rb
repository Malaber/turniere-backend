# frozen_string_literal: true

class UserService
  def initialize(user)
    @user = user
  end

  def bet!(match, team)
    validate_bet! match, team
    @user.bets.create! match:, team:
  end

  private

  def validate_bet!(match, team)
    if team.nil?
      raise UserServiceError, 'Betting on no team in a playoff match is not supported' unless match.group_match?
    else
      raise UserServiceError, 'The given team is not involved in the given match' unless match.teams.include? team
    end
    raise UserServiceError, 'This user already created a bet on this match' if match.bets.map(&:user).include? @user
    raise UserServiceError, "Betting is not allowed while match is #{match.state}" \
      unless %w[not_ready not_started].include? match.state
  end
end
