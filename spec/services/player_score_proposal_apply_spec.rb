# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/player_score_setup'

RSpec.describe PlayerScoreProposalApply do
  include PlayerScoreSetup
  before { setup_player_scores }
  let(:payload) { agree.locked_payload.deep_stringify_keys }

  it 'applies points once without finishing, selecting winners or advancing brackets' do
    expect(PopulateMatchBelowAndSave).not_to receive(:call)
    expect(UpdateGroupsGroupScoresAndSave).not_to receive(:call)
    expect(described_class.call(@leader, payload)).to eq(:applied)
    expect(described_class.call(@leader, payload)).to eq(:duplicate)
    expect(@match.reload).to be_in_progress
    expect(@match.winner).to be_nil
    expect(@stage.reload).to be_in_progress
    expect(PlayerScoreReceipt.count).to eq(1)
    expect(@follower.matches.first.match_scores.pluck(:points)).to eq([0, 0])
    replicate
    expect(@remote.reload.match_scores.order(:id).pluck(:points)).to eq([7, 10])
  end

  it 'keeps implausible but well-shaped scores live without declaring a winner' do
    data = payload
    data['scores'] = data['scores'].transform_values { 1000 }
    expect(described_class.call(@leader, data)).to eq(:applied)
    expect(@match.reload.match_scores.pluck(:points)).to eq([1000, 1000])
    expect(@match).to be_in_progress
    expect(@match.winner).to be_nil
    expect(@stage.reload).to be_in_progress
  end

  it 'rejects local status changed since the follower snapshot' do
    data = payload
    @match.update!(state: :finished)
    expect(described_class.call(@leader, data)).to eq(:rejected_state)
    expect(@match.match_scores.pluck(:points)).to eq([0, 0])
  end

  it 'rejects a stale agreement after stopping and restarting the match' do
    data = payload
    @match.update!(state: :not_started)
    @match.update!(state: :in_progress)
    expect(described_class.call(@leader, data)).to eq(:rejected_revision)
  end

  it 'rejects unrelated tournament identities, malformed points and administrative fields' do
    data = payload
    [data.merge('tournament_id' => @leader.id + 999), data.merge('state' => 'finished'),
     data.merge('scores' => { @leader.teams.first.id.to_s => -1 })].each do |invalid|
      expect { described_class.call(@leader, invalid) }.to raise_error(PlayerScoreProposalService::Invalid)
    end
    expect(PlayerScoreReceipt.count).to eq(0)
    expect(@match.match_scores.pluck(:points)).to eq([0, 0])
  end

  it 'rejects fabricated participating teams without touching scores' do
    data = payload
    data['team_ids'] = [999_998, 999_999]
    data['scores'] = { '999998' => 7, '999999' => 10 }
    expect(described_class.call(@leader, data)).to eq(:rejected_teams)
    expect(@match.match_scores.pluck(:points)).to eq([0, 0])
  end

  it 'does not process new IDs for a match already handled' do
    data = payload
    described_class.call(@leader, data)
    data['proposal_id'] = SecureRandom.uuid
    data['base_score_revision'] = @match.reload.score_revision
    expect(described_class.call(@leader, data)).to eq(:duplicate)
  end
end
