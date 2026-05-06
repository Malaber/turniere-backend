# frozen_string_literal: true

RSpec.describe AddGroupStageToTournament, type: :interactor do
  let(:empty_tournament_context) do
    AddGroupStageToTournament.call(tournament: @empty_tournament, groups: @groups)
  end

  let(:group_stage_tournament_context) do
    AddGroupStageToTournament.call(tournament: @group_stage_tournament, groups: @groups)
  end

  before do
    @empty_tournament = create(:stageless_tournament)
    @group_stage_tournament = create(:group_stage_tournament, stage_count: 0, group_count: 0)
    @group_stage = create(:group_stage)
    @groups = Hash[1 => create_list(:team, 4), 2 => create_list(:team, 4)].values
    @tournament_service_defaults = [78_345, 2_387]
  end

  context 'GroupStageService mocked' do
    before do
      expect(class_double('GroupStageService').as_stubbed_const(transfer_nested_constants: true))
        .to receive(:generate_group_stage).with(@groups)
                                          .and_return(@group_stage)
    end

    context 'empty tournament' do
      before do
        allow(class_double('TournamentService').as_stubbed_const(transfer_nested_constants: true))
          .to receive(:calculate_default_amount_of_teams_advancing)
          .with(@empty_tournament.playoff_teams_amount, @group_stage.groups.size)
          .and_return(@tournament_service_defaults)
      end

      it 'succeeds' do
        expect(empty_tournament_context).to be_a_success
      end

      it 'adds group stage to the tournament' do
        expect(empty_tournament_context.tournament.stages.first).to eq(@group_stage)
      end

      it 'sets default for instant_finalists_amount' do
        expect(empty_tournament_context.tournament.instant_finalists_amount).to eq(@tournament_service_defaults.first)
      end

      it 'sets default for intermediate_round_participants_amount' do
        expect(empty_tournament_context.tournament.intermediate_round_participants_amount)
          .to eq(@tournament_service_defaults.second)
      end
    end
  end

  context 'empty groups' do
    before do
      expect(class_double('GroupStageService').as_stubbed_const(transfer_nested_constants: true))
        .to receive(:generate_group_stage).with(@groups)
                                          .and_raise('Cannot generate group stage without groups')
    end

    it 'playoff generation fails' do
      expect(empty_tournament_context).to be_a_failure
    end
  end

  context 'unequal group sizes' do
    before do
      expect(class_double('GroupStageService').as_stubbed_const(transfer_nested_constants: true))
        .to receive(:generate_group_stage).with(@groups)
                                          .and_raise('Groups need to be equal size')
    end

    it 'playoff generation fails' do
      expect(empty_tournament_context).to be_a_failure
    end
  end

  context 'tournament where group stage is already generated' do
    it 'does not add group stage' do
      expect(group_stage_tournament_context).to be_a_failure
    end
  end
end
