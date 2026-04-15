# frozen_string_literal: true

RSpec.describe StatisticsService do
  before do
    # build tournament with predictable test data
    tournament = create(:tournament)
    group_stage = create(:group_stage)
    @group_stage = group_stage
    group = group_stage.groups.first
    @most_dominant_score = create(:group_score,
                                  group_points: 100,
                                  scored_points: 100, received_points: 0)
    @least_dominant_score = create(:group_score,
                                   group_points: 0,
                                   scored_points: 0, received_points: 100)
    group.group_scores << @most_dominant_score
    group.group_scores << @least_dominant_score
    tournament.stages << group_stage
    @service = StatisticsService.new group_stage
  end

  describe '#new' do
    context 'with a playoff stage' do
      it 'throws an exception' do
        expect do
          StatisticsService.new create(:playoff_stage)
        end.to raise_error(RuntimeError)
      end
    end

    context 'with a group stage' do
      it 'succeeds' do
        StatisticsService.new create(:group_stage)
      end
    end
  end

  describe '#most_dominant_score' do
    it 'returns the most dominant group score' do
      expect(@service.most_dominant_score.id).to eq(@most_dominant_score.id)
    end
  end

  describe '#least_dominant_score' do
    it 'returns the least dominant group score' do
      expect(@service.least_dominant_score.id).to eq(@least_dominant_score.id)
    end
  end

  describe '#group_scores' do
    it 'returns an array containing all group scores' do
      expect(@service.group_scores.length).to eq(@group_stage.groups.sum { |group| group.group_scores.size })
    end
  end
end
