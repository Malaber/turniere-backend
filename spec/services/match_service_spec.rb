# frozen_string_literal: true

RSpec.describe MatchService do
  describe 'generates' do
    [
      { team_size: 2 },
      { team_size: 4 },
      { team_size: 8 },
      { team_size: 16 },
      { team_size: 32 },
      { team_size: 64 }
    ].each do |parameters|
      result = parameters[:team_size] / 2
      it "#{result} matches from #{parameters[:team_size]} teams" do
        teams = build_list(:team, parameters[:team_size], tournament: create(:tournament))
        generated_matches = MatchService.generate_matches teams
        expect(generated_matches.size).to eq(result)
      end
    end

    [
      { team_size: 3, result: 2 },
      { team_size: 5, result: 4 },
      { team_size: 6, result: 4 },
      { team_size: 7, result: 4 },
      { team_size: 12, result: 8 },
      { team_size: 17, result: 16 },
      { team_size: 18, result: 16 },
      { team_size: 19, result: 16 },
      { team_size: 22, result: 16 },
      { team_size: 45, result: 32 },
      { team_size: 87, result: 64 },
      { team_size: 102, result: 64 },
      { team_size: 111, result: 64 },
      { team_size: 124, result: 64 },
      { team_size: 132, result: 128 },
      { team_size: 255, result: 128 }
    ].each do |parameters|
      it "generates #{parameters[:result]} matches from #{parameters[:team_size]} teams" do
        teams = build_list(:team, parameters[:team_size], tournament: create(:tournament))
        generated_matches = MatchService.generate_matches teams
        expect(generated_matches.size).to eq(parameters[:result])
      end
    end

    [
      { team_size: 2 },
      { team_size: 4 },
      { team_size: 8 },
      { team_size: 16 },
      { team_size: 32 },
      { team_size: 64 },
      { team_size: 128 },
      { team_size: 256 }

    ].each do |parameters|
      it "the right matchups for powers of 2 (#{parameters[:team_size]})" do
        teams = build_list(:team, parameters[:team_size], tournament: create(:tournament))
        generated_matches = MatchService.generate_matches teams
        generated_matches.each_index do |index|
          match = generated_matches[index]
          first_team = match.match_scores.first.team.name
          second_team = match.match_scores.second.team.name
          expect(first_team).to eq(teams[2 * index].name)
          expect(second_team).to eq(teams[2 * index + 1].name)
        end
      end
    end

    [
      { team_size: 3 },
      { team_size: 5 },
      { team_size: 7 },
      { team_size: 9 },
      { team_size: 19 },
      { team_size: 41 },
      { team_size: 52 },
      { team_size: 111 }

    ].each do |parameters|
      it "the right matchups for team numbers that are not powers of 2 (#{parameters[:team_size]})" do
        team_size = parameters[:team_size]
        teams = build_list(:team, team_size, tournament: create(:tournament))
        generated_matches = MatchService.generate_matches teams
        team_order = []
        generated_matches.each do |match|
          match.match_scores.each do |score|
            team_order << score.team
          end
        end
        expect(team_order).to match_array(teams)
      end
    end

    [
      { team_size: 3, single_team_matches: 1 },
      { team_size: 5, single_team_matches: 3 },
      { team_size: 6, single_team_matches: 2 },
      { team_size: 17, single_team_matches: 15 },
      { team_size: 34, single_team_matches: 30 },
      { team_size: 65, single_team_matches: 63 },
      { team_size: 138, single_team_matches: 118 },
      { team_size: 276, single_team_matches: 236 }

    ].each do |parameters|
      team_size = parameters[:team_size]
      single_team_matches = parameters[:single_team_matches]
      it "generates #{single_team_matches} empty matches for #{team_size} teams" do
        teams = build_list(:team, team_size, tournament: create(:tournament))
        generated_matches = MatchService.generate_matches teams
        filtered_matches = generated_matches.select(&:single_team?)
        expected_single_team_matches_size = single_team_matches
        expect(filtered_matches.size).to eq(expected_single_team_matches_size)
      end
    end

    it 'raises an exception for for 0 teams' do
      expect { MatchService.generate_matches([]) }.to raise_error 'Cannot generate Matches without teams'
    end

    it 'generates matches with consecutive positions' do
      MatchService.generate_matches(create_list(:team, 7)).sort_by(&:position).each_with_index do |match, i|
        expect(match.position).to eq(i)
      end
    end

    it 'places all given teams into the matches exactly once' do
      teams = create_list(:team, 11)
      expect(MatchService.generate_matches(teams).map(&:teams).flatten).to match_array(teams)
    end
  end
end
