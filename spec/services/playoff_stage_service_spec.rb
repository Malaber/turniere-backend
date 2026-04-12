# frozen_string_literal: true

RSpec.describe PlayoffStageService do
  describe 'generates' do
    [
      { amount: 1 },
      { amount: 3 },
      { amount: 4 },
      { amount: 7 },
      { amount: 23 },
      { amount: 33 },
      { amount: 82 },
      { amount: 359 }
    ].each do |parameters|
      it "#{parameters[:amount]} empty matches" do
        amount = parameters[:amount]
        generated_matches = PlayoffStageService.generate_empty_matches amount
        generated_matches.each_index do |i|
          expect(generated_matches[i].not_ready?).to eq(true)
          expect(generated_matches[i].position).to eq(i)
        end
        expect(generated_matches.size).to eq(amount)
      end
    end
  end

  describe 'generates' do
    [
      { stages: 1 },
      { stages: 2 },
      { stages: 3 },
      { stages: 4 },
      { stages: 5 },
      { stages: 6 },
      { stages: 7 },
      { stages: 8 },
      { stages: 9 },
      { stages: 10 }
    ].each do |parameters|
      it "#{parameters[:stages]} stages with matches provided by #generate_empty_matches" do
        amount_of_empty_stages = parameters[:stages]
        empty_stages = PlayoffStageService.generate_stages_with_empty_matches(amount_of_empty_stages)
        expect(empty_stages.size).to eq(amount_of_empty_stages)
        empty_stages.each_index do |i|
          empty_stage = empty_stages[i]
          expected_empty_stages_size = empty_stages.size - 1 - i
          expect(empty_stage.level).to eq(expected_empty_stages_size)
          expect(empty_stage.matches.size).to eq(2**expected_empty_stages_size)
        end
      end
    end
  end

  describe '#generate_playoff_stages' do
    [
      { team_size: 1, expected_amount_of_playoff_stages: 1 },
      { team_size: 2, expected_amount_of_playoff_stages: 1 },
      { team_size: 3, expected_amount_of_playoff_stages: 2 },
      { team_size: 4, expected_amount_of_playoff_stages: 2 },
      { team_size: 8, expected_amount_of_playoff_stages: 3 },
      { team_size: 9, expected_amount_of_playoff_stages: 4 },
      { team_size: 10, expected_amount_of_playoff_stages: 4 },
      { team_size: 16, expected_amount_of_playoff_stages: 4 },
      { team_size: 24, expected_amount_of_playoff_stages: 5 },
    ].each do |parameters|
      it "generates playoff stages for #{parameters[:team_size]} teams" do
        amount_of_teams = parameters[:team_size]
        expected_amount_of_playoff_stages = parameters[:expected_amount_of_playoff_stages]
        teams = build_list(:team, amount_of_teams)
        stages = PlayoffStageService.generate_playoff_stages(teams, false)
        expect(stages.size).to eq(expected_amount_of_playoff_stages)
        stages.each_index do |i|
          stage = stages[i]
          stage_level = stages.size - i - 1
          expect(stage.level).to eq stage_level
        end
      end
    end

    describe 'number of teams isn\'t a power of two' do
      let(:generated_stages) do
        PlayoffStageService.generate_playoff_stages(create_list(:team, 12), false)
      end

      let(:intermediate_stage) do
        generated_stages.max_by(&:level)
      end

      it 'generates an intermediate stage at the top level' do
        expect(intermediate_stage.state).to eq('intermediate_stage')
      end

      it 'generates normal playoff_stage state stages elsewhere' do
        (generated_stages - [intermediate_stage]).each do |stage|
          expect(stage.state).to eq('playoff_stage')
        end
      end
    end

    describe 'number of teams is a power of two' do
      let(:generated_stages) do
        PlayoffStageService.generate_playoff_stages(create_list(:team, 16), false)
      end

      it 'generates only normal playoff_stage state stages' do
        generated_stages.each do |stage|
          expect(stage.state).to eq('playoff_stage')
        end
      end
    end
  end

  describe '#populate_match_below' do
    before :each do
      @tournament = create(:stage_tournament, stage_count: 2)
      @match = @tournament.stages.find { |s| s.level == 2 }.matches.first
      @match.state = :finished
      @match.match_scores.each_with_index do |ms, i|
        ms.points = i
        ms.save
      end
      @match.save
      @companion_match = @tournament.stages.find { |s| s.level == 2 }.matches.second
      @companion_match.match_scores.each_with_index do |ms, i|
        ms.points = i
        ms.save
      end
      @match_to_find = @tournament.stages.find { |s| s.level == 1 }.matches.first
    end

    context 'match below has no match_scores' do
      before do
        @match_to_find.match_scores = []
        @match_to_find.save
        @test = PlayoffStageService.populate_match_below(@match).first
      end

      it 'finds the correct match and adds two new match_scores to it' do
        expect(@match_to_find.teams).to match_array(@match.winner)
      end

      it 'finds the correct match and changes its state' do
        expect(@match_to_find.state).to eq('not_ready')
      end
    end

    context 'match below has one match_score with the winning team' do
      before do
        @match_to_find.match_scores = create_list(:match_score, 1, team: @match.winner)
        @match_to_find.save
        @test = PlayoffStageService.populate_match_below(@match).first
      end

      it 'finds the correct match and adds no match_score' do
        expect(@test.teams).to match_array(@match.winner)
      end

      it 'finds the correct match and changes its state' do
        expect(@test.state).to eq('not_ready')
      end
    end

    context 'match below has one match_score with an unknown team' do
      before do
        @match_to_find.match_scores = create_list(:match_score, 1, team: create(:team), points: 1337)
        @match_to_find.save
        @test = PlayoffStageService.populate_match_below(@match).first
      end

      it 'finds the correct match and replaces the match_score' do
        expect(@test.teams).to match_array(@match.winner)
        expect(@test.match_scores.first.points).to_not be(1337)
      end

      it 'finds the correct match and changes its state' do
        expect(@test.state).to eq('not_ready')
      end
    end

    context 'match below has one match_score with the correct team' do
      before do
        @match_to_find.match_scores = create_list(:match_score, 1, team: @match.winner, points: 42)
        @match_to_find.save
        @test = PlayoffStageService.populate_match_below(@match).first
      end

      it 'finds the correct match and replaces nothing' do
        expect(@test.teams).to match_array(@match.winner)
        expect(@test.match_scores.first.points).to be(42)
      end

      it 'finds the correct match and changes its state' do
        expect(@test.state).to eq('not_ready')
      end
    end

    context 'match below has two match_scores with the correct teams' do
      before do
        @companion_match.state = :finished
        @companion_match.save
        @match_to_find.match_scores = [create(:match_score, team: @match.winner),
                                       create(:match_score, team: @companion_match.winner)]
        @match_to_find.save
        @test = PlayoffStageService.populate_match_below(@match).first
      end

      it 'finds the correct match and replaces nothing' do
        expect(@test.teams).to match_array([@match.winner, @companion_match.winner])
      end

      it 'finds the correct match and changes its state' do
        expect(@test.state).to eq('not_started')
      end
    end

    context 'when the current match is the final of a tournament with a group stage' do
      before do
        @tournament = create(:group_stage_tournament, stage_count: 1)
        @final_match = @tournament.stages.reject { |stage| stage.level == -1 }.max_by(&:level).matches.first
        @final_match.state = :finished
        @final_match.match_scores.each_with_index do |match_score, index|
          match_score.points = index
          match_score.save!
        end
        @final_match.save!
      end

      it 'does not treat the group stage as a lower playoff stage' do
        expect(PlayoffStageService.populate_match_below(@final_match)).to eq([])
      end
    end
  end
end
