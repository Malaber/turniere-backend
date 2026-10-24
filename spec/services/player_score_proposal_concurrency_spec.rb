# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/player_score_setup'

RSpec.describe 'Player score proposal concurrency', type: :request do
  self.use_transactional_tests = false
  include PlayerScoreSetup

  before do
    @existing_user_ids = User.pluck(:id)
    setup_player_scores
  end
  after do
    @follower&.destroy!
    @leader&.destroy!
    User.where.not(id: @existing_user_ids).find_each(&:destroy!)
  end

  def concurrently(*operations)
    ready = Queue.new
    start = Queue.new
    threads = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          operation.call
        end
      end
    end
    operations.size.times { ready.pop }
    operations.size.times { start << true }
    threads.map(&:value)
  end

  it 'locks one agreement when both teams submit concurrently' do
    match_id = @remote.id
    team_ids = @teams.map(&:id)
    player_ids = [@players.first.id, @players.last.id]
    scores = remote_scores
    concurrently(*[0, 1].map do |index|
      lambda do
        PlayerScoreProposalService.submit!(match: Match.find(match_id), user: User.find(player_ids[index]),
                                          team_id: team_ids[index], scores: scores)
      end
    end)
    proposals = PlayerScoreProposal.where(tournament: @follower)
    expect(proposals.count).to eq(1)
    expect(proposals.first.locked_at).to be_present
  end

  it 'serializes simultaneous leader polls' do
    payload = agree.locked_payload.deep_stringify_keys
    tournament_id = @leader.id
    concurrently(
      -> { PlayerScoreProposalApply.call(Tournament.find(tournament_id), payload) },
      -> { PlayerScoreProposalApply.call(Tournament.find(tournament_id), payload) }
    )
    expect(PlayerScoreReceipt.where(tournament_id: tournament_id).count).to eq(1)
  end

  it 'preserves an administrator racing with the first apply' do
    payload = agree.locked_payload.deep_stringify_keys
    tournament_id = @leader.id
    # Same transaction lock as the admin score endpoint; either order leaves admin last.
    concurrently(
      -> { PlayerScoreProposalApply.call(Tournament.find(tournament_id), payload) },
      lambda do
        Tournament.transaction do
          TournamentTransactionLogger.lock_tournament!(Tournament.find(tournament_id))
          match = Match.find(@match.id)
          match.match_scores.first.update!(points: 5)
          match.update!(player_score_blocked: true, score_revision: match.score_revision + 1)
        end
      end
    )
    expect(@match.reload.match_scores.first.points).to eq(5)
  end
end
