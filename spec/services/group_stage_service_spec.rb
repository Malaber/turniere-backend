# frozen_string_literal: true

RSpec.describe GroupStageService do
  before do
    @teams1 = create_list(:team, 4)
    @teams2 = create_list(:team, 4)
    @prepared_groups = Hash[1 => @teams1, 2 => @teams2].values
  end
  describe '#generate_group_stage' do
    let(:prepared_groups_groupstage) do
      GroupStageService.generate_group_stage(@prepared_groups)
    end

    it 'returns a stage object' do
      expect(prepared_groups_groupstage).to be_a(Stage)
    end

    it 'assigns the correct state' do
      expect(prepared_groups_groupstage.state).to eq('in_progress')
    end

    it 'assigns unique numbers to each group' do
      groups = prepared_groups_groupstage.groups
      groups.sort_by(&:number).each_with_index do |group, i|
        expect(group.number).to eq(i + 1)
      end
    end

    it 'returns a stage object with level -1' do
      expect(prepared_groups_groupstage.level).to be(-1)
    end

    it 'adds the provided groups to the stage' do
      expect(prepared_groups_groupstage.teams).to match_array(@prepared_groups.flatten)
    end

    it 'adds GroupScore objects for every team present in the group' do
      expect(prepared_groups_groupstage.groups.map { |g| g.group_scores.map(&:team) }.flatten)
        .to match_array(@prepared_groups.flatten)
    end

    it 'raises exception when given different sizes of groups' do
      unequal_groups = @prepared_groups
      unequal_groups.first.pop
      expect { GroupStageService.generate_group_stage(unequal_groups) }
        .to raise_exception 'Groups need to be equal size'
    end

    it 'raises exception when given no groups' do
      expect { GroupStageService.generate_group_stage([]) }
        .to raise_exception 'Cannot generate group stage without groups'
    end
  end

  # TODO test get_advancing_teams when test data for running group stage is ready

  describe '#get_group_object_from' do
    it 'returns a group' do
      group = GroupStageService.get_group_object_from(@teams1)
      expect(group).to be_a(Group)
    end
  end

  describe '#generate_all_matches_between' do
    it 'generates a list of not started matches' do
      matches = GroupStageService.generate_all_matches_between(@teams2)
      matches.each do |match|
        expect(match).to be_a(Match)
        match_state = match.state
        expect(match_state).to eq('not_started')
      end
    end

    it 'generates the right amount of matches' do
      matches = GroupStageService.generate_all_matches_between(@teams2)
      # (1..@teams2.size-1).sum -> 1. Team has to play against n-1 teams; second against n-2 ....
      expect(matches.size).to be((1..@teams2.size - 1).sum)
    end

    it 'gives matches exclusive positions' do
      matches = GroupStageService.generate_all_matches_between(@teams2)
      match_positions = matches.map(&:position)
      expect(match_positions.length).to eq(match_positions.uniq.length)
    end

    it 'doesn\'t match a team against itself' do
      matches = GroupStageService.generate_all_matches_between(@teams1)
      matches.each do |match|
        expect(match.teams.first).to_not eq(match.teams.second)
      end
    end
  end

  describe '#update_group_scores' do
    shared_examples_for 'only_return_group_scores' do
      it 'only returns group_scores' do
        @changed_group_scores.each do |gs|
          expect(gs).to be_a(GroupScore)
        end
      end
    end

    context 'with only undecided matches' do
      before do
        @group = create(:group, match_factory: :running_group_match)
        @group.matches.each do |match|
          match.match_scores.each do |ms|
            ms.points = 42
            ms.save!
          end
        end
        @changed_group_scores = GroupStageService.update_group_scores(@group)
      end

      it 'assigns one point to every team' do
        @changed_group_scores.map(&:group_points).each do |points|
          expect(points).to be(1)
        end
      end

      it 'returns correct values for received_points' do
        @changed_group_scores.map(&:received_points).each do |points|
          expect(points).to be(42)
        end
      end

      it 'returns correct values for scored_points' do
        @changed_group_scores.map(&:scored_points).each do |points|
          expect(points).to be(42)
        end
      end

      it_should_behave_like 'only_return_group_scores'
    end

    context 'with only decided matches' do
      before do
        @group = create(:group, match_factory: :running_group_match)
        @group.matches.each_with_index do |match, i|
          match.match_scores.each_with_index do |ms, j|
            match_score_number = i + j
            ms.points = match_score_number
            ms.save!
          end
        end
        @changed_group_scores = GroupStageService.update_group_scores(@group)
      end

      it 'assigns the right amount of points' do
        winning_teams = @changed_group_scores.select { |gs| gs.group_points == 3 }
        losing_teams = @changed_group_scores.select { |gs| gs.group_points == 0 }
        # Assure that half of the teams won and got 3 points
        expect(winning_teams.size).to be(@changed_group_scores.size / 2)
        # and half of them lost and got 0
        expect(losing_teams.size).to be(@changed_group_scores.size / 2)
      end

      it_should_behave_like 'only_return_group_scores'
    end
  end

  describe '#teams_sorted_by_group_scores' do
    before do
      @group_to_sort = create(:group, match_count: 10, match_factory: :filled_group_match)
    end

    let(:sorted_teams) do
      GroupStageService.teams_sorted_by_group_scores(@group_to_sort)
    end

    let(:sorted_teams_grouped_by_group_points) do
      sorted_teams.group_by { |t| @group_to_sort.group_scores.find_by(team: t).group_points }.values
    end

    it 'sorts the teams after group_scores first' do
      i = 0
      while i < (sorted_teams.size - 1)
        expect(@group_to_sort.group_scores.find_by(team: sorted_teams[i]).group_points)
          .to be >= @group_to_sort.group_scores.find_by(team: sorted_teams[i + 1]).group_points
        i += 1
      end
    end

    it 'sorts the teams after difference_in_points second' do
      sorted_teams_grouped_by_group_points.each do |teams|
        i = 0
        while i < (teams.size - 1)
          expect(@group_to_sort.group_scores.find_by(team: teams[i]).difference_in_points)
            .to be >= @group_to_sort.group_scores.find_by(team: teams[i + 1]).difference_in_points
          i += 1
        end
      end
    end

    it 'uses the direct comparison when the first three criteria are tied' do
      group = create(:group, match_count: 0)
      team_a = create(:team)
      team_b = create(:team)

      create(:group_match, group: group, state: :finished).tap do |match|
        create(:match_score, match: match, team: team_a, points: 4)
        create(:match_score, match: match, team: team_b, points: 2)
      end

      create(:group_score, group: group, team: team_a, group_points: 3, scored_points: 4, received_points: 2)
      create(:group_score, group: group, team: team_b, group_points: 3, scored_points: 4, received_points: 2)

      expect(GroupStageService.teams_sorted_by_group_scores(group.reload)).to eq([team_a, team_b])
    end
  end

  describe '.ranking_decision_for' do
    let(:tournament) do
      create(:prepared_group_stage_tournament,
             teams_count: 0,
             playoff_teams_amount: 2,
             instant_finalists_amount: 2,
             intermediate_round_participants_amount: 0,
             group_stage: group_stage)
    end
    let(:group_stage) { create(:group_stage, tournament: create(:tournament, teams_count: 0), group_count: 0) }
    let(:group) { create(:group, stage: group_stage, match_count: 0, number: 1) }
    let(:team_a) { create(:team, tournament: tournament, name: 'A') }
    let(:team_b) { create(:team, tournament: tournament, name: 'B') }
    let(:team_c) { create(:team, tournament: tournament, name: 'C') }
    let(:team_d) { create(:team, tournament: tournament, name: 'D') }

    before do
      group_stage.groups = [group]
      group_stage.level = -1
      group_stage.save!
    end

    it 'returns direct-comparison metadata for teams separated by head-to-head' do
      create(:group_match, group: group, state: :finished).tap do |match|
        create(:match_score, match: match, team: team_a, points: 4)
        create(:match_score, match: match, team: team_b, points: 2)
      end

      score_a = create(:group_score, group: group, team: team_a, group_points: 3, scored_points: 4, received_points: 2)
      score_b = create(:group_score, group: group, team: team_b, group_points: 3, scored_points: 4, received_points: 2)

      GroupStageService.send(:recalculate_position_of_group_scores!, [score_a, score_b]).each(&:save!)

      expect(GroupStageService.ranking_decision_for(score_a)).to include(
        resolved_by: 'direct_comparison',
        compared_with_team_id: team_b.id,
        direct_comparison_result: 'won',
        hidden_points_result: 'not_played',
        tied: false,
        needs_decider_match: false
      )
      expect(GroupStageService.ranking_decision_for(score_b)).to include(
        resolved_by: 'direct_comparison',
        compared_with_team_id: team_a.id,
        direct_comparison_result: 'lost',
        hidden_points_result: 'not_played',
        tied: false,
        needs_decider_match: false
      )
    end

    it 'keeps shared positions and requests a decider only when an unresolved tie crosses the cutoff' do
      tournament.update!(playoff_teams_amount: 1, instant_finalists_amount: 1, intermediate_round_participants_amount: 0)

      create(:group_match, group: group, state: :finished).tap do |match|
        create(:match_score, match: match, team: team_a, points: 2)
        create(:match_score, match: match, team: team_b, points: 2)
      end

      score_a = create(:group_score, group: group, team: team_a, group_points: 7, scored_points: 4, received_points: 1)
      score_b = create(:group_score, group: group, team: team_b, group_points: 7, scored_points: 4, received_points: 1)
      score_c = create(:group_score, group: group, team: team_c, group_points: 3, scored_points: 2, received_points: 3)
      score_d = create(:group_score, group: group, team: team_d, group_points: 0, scored_points: 1, received_points: 7)

      GroupStageService.send(:recalculate_position_of_group_scores!, [score_a, score_b, score_c, score_d]).each(&:save!)

      expect([score_a.position, score_b.position, score_c.position, score_d.position]).to eq([1, 1, 3, 4])
      expect(GroupStageService.ranking_decision_for(score_a)).to include(
        resolved_by: 'tie',
        direct_comparison_result: 'draw',
        hidden_points_result: 'not_played',
        tied: true,
        needs_decider_match: true
      )
      expect(GroupStageService.ranking_decision_for(score_b)).to include(
        resolved_by: 'tie',
        direct_comparison_result: 'draw',
        hidden_points_result: 'not_played',
        tied: true,
        needs_decider_match: true
      )
    end

    it 'marks unresolved ties outside the advancing cutoff without requesting a decider' do
      tournament.update!(playoff_teams_amount: 2, instant_finalists_amount: 2, intermediate_round_participants_amount: 0)

      score_a = create(:group_score, group: group, team: team_a, group_points: 9, scored_points: 5, received_points: 1, position: 1)
      score_b = create(:group_score, group: group, team: team_b, group_points: 6, scored_points: 4, received_points: 2, position: 2)
      score_c = create(:group_score, group: group, team: team_c, group_points: 3, scored_points: 2, received_points: 3)
      score_d = create(:group_score, group: group, team: team_d, group_points: 3, scored_points: 2, received_points: 3)

      GroupStageService.send(:recalculate_position_of_group_scores!, [score_a, score_b, score_c, score_d]).each(&:save!)

      expect([score_a.position, score_b.position, score_c.position, score_d.position]).to eq([1, 2, 3, 3])
      expect(GroupStageService.ranking_decision_for(score_c)).to include(
        resolved_by: 'tie',
        hidden_points_result: 'not_played',
        tied: true,
        needs_decider_match: false
      )
      expect(GroupStageService.ranking_decision_for(score_d)).to include(
        resolved_by: 'tie',
        hidden_points_result: 'not_played',
        tied: true,
        needs_decider_match: false
      )
    end

    it 'uses the decider hidden points to resolve a cutoff tie' do
      tournament.update!(playoff_teams_amount: 1, instant_finalists_amount: 1, intermediate_round_participants_amount: 0)

      create(:group_match, group: group, state: :finished).tap do |match|
        create(:match_score, match: match, team: team_a, points: 2)
        create(:match_score, match: match, team: team_b, points: 2)
      end
      create(:group_match, group: group, state: :finished, decider: true).tap do |match|
        create(:match_score, match: match, team: team_a, hidden_points: 5)
        create(:match_score, match: match, team: team_b, hidden_points: 3)
      end

      score_a = create(:group_score, group: group, team: team_a, group_points: 7, scored_points: 4, received_points: 1)
      score_b = create(:group_score, group: group, team: team_b, group_points: 7, scored_points: 4, received_points: 1)
      score_c = create(:group_score, group: group, team: team_c, group_points: 3, scored_points: 2, received_points: 3)
      score_d = create(:group_score, group: group, team: team_d, group_points: 0, scored_points: 1, received_points: 7)

      GroupStageService.send(:recalculate_position_of_group_scores!, [score_a, score_b, score_c, score_d]).each(&:save!)

      expect([score_a.position, score_b.position, score_c.position, score_d.position]).to eq([1, 2, 3, 4])
      expect(GroupStageService.ranking_decision_for(score_a)).to include(
        resolved_by: 'hidden_points',
        direct_comparison_result: 'draw',
        hidden_points_result: 'won',
        tied: false,
        needs_decider_match: false
      )
    end
  end

  describe '#get_advancing_teams' do
    context 'when special case for po2 applies' do
      before do
        teams = create_list(:team, 32)

        # put the teams in groups of four
        groups = teams.each_slice(4).to_a

        # iterate over all groups and number the teams in their name
        groups.each_with_index do |group, group_index|
          group.each_with_index do |team, team_index|
            team.name = "#{team.name} #{group_index} #{team_index}"
            team.save!
          end
        end

        # Generate the group stage
        @group_stage = GroupStageService.generate_group_stage(groups)

        @tournament = create(:prepared_group_stage_tournament,
                             group_stage: @group_stage,
                             teams: teams,
                             playoff_teams_amount: 16,
                             instant_finalists_amount: 16,
                             intermediate_round_participants_amount: 0)
        # iterate over all groups and update the matches within to all be decided
        @group_stage.groups.each do |group|
          group.matches.each do |match|
            match.match_scores.each do |ms|
              # give the team 10 points minus the number in their name
              # this results in the team 0 always winning and getting to place 1 in the group etc.
              ms.points = 10 - ms.team.name.split(' ').last.to_i
              ms.save!
            end
            match.state = 'finished'
            match.save!
          end
          group_scores = GroupStageService.update_group_scores(group)
          group_scores.each(&:save!)

          group.group_scores.each(&:reload)
        end
      end

      it 'returns the correct amount of teams' do
        advancing_teams = GroupStageService.get_advancing_teams(@group_stage)
        expect(advancing_teams.size).to be(16)
      end

      it 'returns the correct teams in the correct order' do
        advancing_teams = GroupStageService.get_advancing_teams(@group_stage)
        advancing_teams.each_with_index do |team, i|
          # if index is even, the team should be of a first place; end in a 0
          # if index is odd, the team should be of a second place; end in a 1
          team_quality = team.name.split(' ').last.to_i
          expect(team_quality % 2).to be(i % 2)
        end
      end

      it 'spaces groups apart, so you meet your group only in finale' do
        group_first_matchups_expected = {
          0 => 4,
          1 => 5,
          2 => 6,
          3 => 7,
          4 => 0,
          5 => 1,
          6 => 2,
          7 => 3
        }
        advancing_teams = GroupStageService.get_advancing_teams(@group_stage)
        advancing_teams.each_slice(2).to_a.each do |matchup|
          # this is the team that landed a first place in the group
          first_place_team = matchup[0].name.split(' ')[1].to_i
          # this is the team that landed a second place in the group
          second_place_team = matchup[1].name.split(' ')[1].to_i
          expect(group_first_matchups_expected[first_place_team]).to eq(second_place_team)
        end
      end
    end
  end
end
