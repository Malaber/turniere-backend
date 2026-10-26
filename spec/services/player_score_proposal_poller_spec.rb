# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/player_score_setup'

RSpec.describe PlayerScoreProposalPoller do
  include PlayerScoreSetup
  before { setup_player_scores }

  it 'retries offline failures without advancing the cursor or changing public scores' do
    agree
    poller = described_class.new(@leader)
    allow(poller).to receive(:fetch).and_raise(Net::ReadTimeout)
    expect { poller.poll! }.to raise_error(Net::ReadTimeout)
    expect(@leader.reload.score_proposal_cursor).to eq(0)
    expect(@match.reload.match_scores.pluck(:points)).to eq([0, 0])
  end

  it 'processes a locked batch once and ignores repeated polling results' do
    data = agree.locked_payload.deep_stringify_keys
    poller = described_class.new(@leader)
    allow(poller).to receive(:fetch).and_return('proposals' => [data])
    2.times { poller.poll! }
    expect(PlayerScoreReceipt.count).to eq(1)
    expect(@leader.reload.score_proposal_cursor).to eq(data['sequence'])
    expect(@remote.reload.match_scores.pluck(:points)).to eq([0, 0])
    replicate
    expect(@remote.reload.match_scores.pluck(:points)).to eq([7, 10])
  end

  it 'uses lock order rather than creation order when earlier proposals agree later' do
    first = propose
    second_match = Match.create!(stage: @remote.stage, state: :in_progress, sync_source_id: 999)
    @teams.each { |team| MatchScore.create!(match: second_match, team: team, points: 0) }
    second_match.reload
    [0, 2].each do |player|
      PlayerScoreProposalService.submit!(match: second_match, user: @players[player],
                                        team_id: @teams[player == 2 ? 1 : 0].id, scores: remote_scores)
    end
    second = PlayerScoreProposal.find_by!(source_match_id: 999)
    propose(2)
    expect(first.reload.locked_sequence).to be > second.locked_sequence
  end

  it 'only performs an authenticated outbound GET and rejects redirects' do
    poller = described_class.new(@leader)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    expect(http).to receive(:request) do |request, &block|
      expect(request).to be_a(Net::HTTP::Get)
      expect(request.path).to eq('/tournaments/99/locked_score_proposals?after=0')
      expect(request['Authorization']).to eq('Bearer secret')
      block.call(Net::HTTPFound.new('1.1', '302', 'Found'))
    end
    expect { poller.poll! }.to raise_error(PlayerScoreProposalService::Invalid)
  end
end
