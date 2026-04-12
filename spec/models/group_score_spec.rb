# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GroupScore, type: :model do
  describe 'association' do
    it { should belong_to :team }
    it { should belong_to :group }
  end

  describe '#<=>' do
    let(:group) { create(:group, match_count: 0) }
    let(:team_a) { create(:team) }
    let(:team_b) { create(:team) }
    let(:team_c) { create(:team) }

    let(:group_score_a) do
      create(:group_score, group: group, team: team_a, group_points: 6, scored_points: 7, received_points: 4)
    end
    let(:group_score_b) do
      create(:group_score, group: group, team: team_b, group_points: 6, scored_points: 7, received_points: 4)
    end

    it 'prefers the winner of the direct comparison when the first three criteria are tied' do
      create(:group_match, group: group, state: :finished).tap do |match|
        create(:match_score, match: match, team: team_a, points: 3)
        create(:match_score, match: match, team: team_c, points: 1)
      end

      create(:group_match, group: group, state: :finished).tap do |match|
        create(:match_score, match: match, team: team_a, points: 4)
        create(:match_score, match: match, team: team_b, points: 2)
      end

      group_score_a.reload
      group_score_b.reload

      expect(group_score_a <=> group_score_b).to eq(-1)
      expect(group_score_b <=> group_score_a).to eq(1)
    end

    it 'keeps the teams tied when their direct comparison was a draw' do
      create(:group_match, group: group, state: :finished).tap do |match|
        create(:match_score, match: match, team: team_a, points: 2)
        create(:match_score, match: match, team: team_b, points: 2)
      end

      group_score_a.reload
      group_score_b.reload

      expect(group_score_a <=> group_score_b).to eq(0)
      expect(group_score_b <=> group_score_a).to eq(0)
    end
  end
end
