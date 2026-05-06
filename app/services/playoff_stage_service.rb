# frozen_string_literal: true

class PlayoffStageService
  class << self
    # Generates the playoff stage given the tournament
    #
    # @param teams [Array] The teams to generate the playoff stages with
    # @return [Array] the generated playoff stages
    def generate_playoff_stages(teams, randomize_matches)
      playoffs = []
      stage_count = calculate_required_stage_count(teams.size)
      # initial_matches are the matches in the first stage; this is the only stage filled with teams from the start on
      initial_matches = MatchService.generate_matches(teams)
      initial_matches = initial_matches.shuffle.each_with_index { |m, i| m.position = i } if randomize_matches
      initial_stage = Stage.new level: stage_count - 1, matches: initial_matches
      initial_stage.state = :intermediate_stage unless initial_stage.matches.find(&:single_team?).nil?
      playoffs << initial_stage
      # empty stages are the stages, the tournament is filled with to have the matches ready for later
      empty_stages = generate_stages_with_empty_matches(stage_count - 1, include_third_place_match: teams.size > 3)
      playoffs.concat empty_stages
      playoffs
    end

    # Generates given number of empty stages
    #
    # @param stage_count [Integer] number of stages to generate
    # @return [Array] the generated stages
    def generate_stages_with_empty_matches(stage_count, include_third_place_match: false)
      empty_stages = []
      stage_count.times do |i|
        match_count = 2**i
        match_count += 1 if include_third_place_match && i.zero?
        stage = Stage.new level: i, matches: generate_empty_matches(match_count)
        empty_stages << stage
      end
      # as we are generating the stages in the wrong order (starting with the lowest number of matches (which is
      # the final stage)) they need to be reversed
      empty_stages.reverse!
    end

    # Generates a number of empty matches to fill later stages
    #
    # @param amount [Integer] the amount of matches to generate
    # @return [Array] the generated matches
    def generate_empty_matches(amount)
      matches = []
      amount.times do |i|
        match = Match.new state: :not_ready, position: i
        matches << match
      end
      matches
    end

    # Calculates how many stages are required for given number of teams
    #
    # @param number_of_teams [Integer] the teams number of teams to calculate amount of stages
    # @return [Integer] amount of required stages
    def calculate_required_stage_count(number_of_teams)
      if number_of_teams == 1
        1
      else
        # black voodoo magic
        stage_count = Math.log(Utils.next_power_of_two(number_of_teams)) / Math.log(2)
        stage_count -= 1 if Utils.po2?(number_of_teams)
        stage_count.to_int
      end
    end

    # Populates the match below given match with the winners of the matches above
    #
    # @param current_match [Match] The Match which finished, the match below it gets populated
    # @return [Array] the objects that changed and need to be saved
    def populate_match_below(current_match)
      current_stage = current_match.stage
      next_stage = current_stage.tournament.stages
                                .select { |stage| stage.matches.any? && stage.level < current_stage.level }
                                .max_by(&:level)
      # return if next stage does not exist (there are no matches after the finale)
      return [] if next_stage.nil?

      # a "companion" match is the one that with the selected match makes up the two matches
      # of which the winners advance into the match below
      # depending on the position of the match, the companion match is either on the left or right of it
      companion_match = find_companion_match(current_match.position, current_stage)
      return populate_final_stage_matches(current_match, companion_match, next_stage) if semifinal_match?(
        current_stage, next_stage
      )

      winners = get_winners_of(companion_match, current_match)
      populate_match!(match: next_stage.matches.find { |m| m.position == current_match.position / 2 }, teams: winners)
    end

    private

    def find_companion_match(current_position, current_stage)
      companion_match_position = current_position.even? ? current_position + 1 : current_position - 1
      current_stage.matches.find { |m| m.position == companion_match_position }
    end

    def assign_correct_match_scores!(match_scores, winners)
      case match_scores.size
      when 0
        # when 0 match_scores are already there we create both of them with the respective winner from above
        match_scores = winners.map { |winner| MatchScore.new(team: winner) }
      when 1
        # when 1 match_score is present, we need to check which team is contained within and add the other team as well
        if match_scores.first.team == winners.first
          match_scores.push MatchScore.new(team: winners.second)
        elsif match_scores.first.team == winners.second
          match_scores.push MatchScore.new(team: winners.first)
        else
          match_scores.first.destroy
          match_scores = winners.map { |winner| MatchScore.new(team: winner) }
        end
      when 2
        # when 2 match_scores are present, the teams just get overwritten
        match_scores.first.team = winners.first
        match_scores.second.team = winners.second
      end
      match_scores
    end

    def populate_match!(match:, teams:)
      match_scores = match.match_scores.sort_by(&:id)
      match_scores = assign_correct_match_scores!(match_scores, teams)
      match_scores = match_scores.select { |ms| ms.team.present? }
      match.match_scores = match_scores
      match.state = if match.match_scores.empty? || match.match_scores.size == 1
                      :not_ready
                    elsif match.match_scores.size == 2
                      :not_started
                    else
                      raise 'Unprocessable amount of match_scores found'
                    end
      [match, match_scores].flatten
    end

    def get_winners_of(companion_match, current_match)
      matches = [current_match, companion_match].sort_by(&:position)
      matches.map(&:winner)
    end

    def get_losers_of(companion_match, current_match)
      matches = [current_match, companion_match].sort_by(&:position)
      matches.map(&:loser)
    end

    def semifinal_match?(current_stage, next_stage)
      current_stage.level == 1 && next_stage.level.zero? && next_stage.matches.size > 1
    end

    def populate_final_stage_matches(current_match, companion_match, next_stage)
      final_match = next_stage.matches.find { |match| match.position.zero? }
      third_place_match = next_stage.matches.find { |match| match.position == 1 }

      [
        populate_match!(match: final_match, teams: get_winners_of(companion_match, current_match)),
        populate_match!(match: third_place_match, teams: get_losers_of(companion_match, current_match))
      ].flatten
    end
  end
end
