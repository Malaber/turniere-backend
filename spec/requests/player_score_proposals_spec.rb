# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/player_score_setup'

RSpec.describe 'Player score proposals', type: :request do
  include PlayerScoreSetup
  before { setup_player_scores }

  def submit(player: 0, team: @teams.first, scores: remote_scores)
    patch "/matches/#{@remote.id}/score_proposal", params: { team_id: team.id, scores: scores },
                                                   headers: @players[player].create_new_auth_token, as: :json
  end

  it 'allows teammates to replace their team proposal but locks agreement exactly once' do
    submit(scores: remote_scores(5, 10))
    expect(response).to have_http_status(:ok)
    submit(player: 1)
    expect(response.parsed_body['proposals'].first['scores']).to eq(remote_scores)
    submit(player: 2, team: @teams.last, scores: remote_scores(6, 10))
    expect(response.parsed_body['locked']).to be(false)
    submit(player: 2, team: @teams.last)
    expect(response.parsed_body['locked']).to be(true)
    expect(PlayerScoreProposal.count).to eq(1)
    submit
    expect(response).to have_http_status(:conflict)
    expect(PlayerScoreProposal.first.revision).to eq(4)
  end

  it 'accepts decider proposals and publishes only leader-applied live points' do
    @match.update!(decider: true)
    replicate
    get "/matches/#{@remote.id}/score_proposal", headers: @players.first.create_new_auth_token
    expect(response.parsed_body['accepting']).to be(true)
    submit
    expect(response).to have_http_status(:ok)
    submit(player: 2, team: @teams.last)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['locked']).to be(true)
    expect(response.parsed_body['accepting']).to be(false)
    expect(@remote.reload.match_scores.pluck(:points)).to eq([0, 0])

    expect(PopulateMatchBelowAndSave).not_to receive(:call)
    expect(UpdateGroupsGroupScoresAndSave).not_to receive(:call)
    payload = PlayerScoreProposal.first.locked_payload.deep_stringify_keys
    expect(PlayerScoreProposalApply.call(@leader, payload)).to eq(:applied)
    expect(PlayerScoreProposalApply.call(@leader, payload)).to eq(:duplicate)
    expect(@match.reload).to be_in_progress
    expect(@match.winner).to be_nil
    expect(@stage.reload).to be_in_progress
    replicate
    expect(@remote.reload).to be_decider
    expect(@remote).to be_in_progress
    expect(@remote.match_scores.order(:id).pluck(:hidden_points)).to eq([7, 10])
    expect(@remote.match_scores.order(:id).pluck(:points)).to eq([0, 0])
    get "/matches/#{@remote.id}/score_proposal", headers: @players.first.create_new_auth_token
    expect(response.parsed_body['official_scores']).to eq(remote_scores)
  end

  it 'rejects opponent impersonation, unauthenticated requests and non-members' do
    submit(team: @teams.last)
    expect(response).to have_http_status(:forbidden)
    patch "/matches/#{@remote.id}/score_proposal", params: { team_id: @teams.first.id, scores: remote_scores }, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "/matches/#{@remote.id}/score_proposal", headers: create(:user).create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'accepts no extra score fields, strings, negative values or lifecycle writes' do
    [remote_scores.merge('state' => 'finished'), remote_scores(-1), remote_scores('7'), remote_scores(1001)].each do |scores|
      submit(scores: scores)
      expect(response).to have_http_status(:unprocessable_content)
    end
    expect(@remote.reload.state).to eq('in_progress')
    expect(@remote.match_scores.pluck(:points)).to eq([0, 0])
  end

  it 'keeps locked proposals private and survives snapshots while the leader is offline' do
    locked = agree
    replicate
    expect(locked.reload.locked_at).to be_present
    expect(@remote.reload.match_scores.pluck(:points)).to eq([0, 0])
    get "/matches/#{@remote.id}"
    expect(response.parsed_body.to_json).not_to include(locked.proposal_id)
    get "/tournaments/#{@follower.id}/locked_score_proposals"
    expect(response).to have_http_status(:unauthorized)
    get "/tournaments/#{@follower.id}/locked_score_proposals", headers: { 'Authorization' => 'Bearer secret' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['proposals'].first['scores'].values).to eq([7, 10])
  end

  it 'rejects stale status and does not allow proposals on leaders' do
    @remote.update!(state: :finished)
    submit
    expect(response).to have_http_status(:conflict)
    @match.teams.first.players << @players.first
    patch "/matches/#{@match.id}/score_proposal", params: { team_id: @match.teams.first.id, scores: @match.match_scores.to_h do |score|
      [score.team_id.to_s, 0]
    end },
                                                  headers: @players.first.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'advertises player capability without exposing sync credentials to participants' do
    get "/tournaments/#{@follower.id}", headers: @players.first.create_new_auth_token
    expect(response.parsed_body['player_score_proposals_enabled']).to be(true)
    expect(response.parsed_body).not_to have_key('sync_target_url')
    expect(response.parsed_body).not_to have_key('sync_auth_token')
  end

  it 'lists only matches for the signed-in player' do
    get "/tournaments/#{@follower.id}/player_score_matches", headers: @players.first.create_new_auth_token
    expect(response.parsed_body['matches'].first['eligible_team_ids']).to eq([@teams.first.id])
    get "/tournaments/#{@follower.id}/player_score_matches", headers: create(:user).create_new_auth_token
    expect(response.parsed_body['matches']).to eq([])
  end

  it 'preserves player and admin values in history and never overwrites an admin correction' do
    payload = agree.locked_payload.deep_stringify_keys
    expect(PlayerScoreProposalApply.call(@leader, payload)).to eq(:applied)
    score = @match.match_scores.find_by!(team: @leader.teams.first)
    patch "/match_scores/#{score.id}", params: { points: 5 }, headers: @leader.owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(PlayerScoreProposalApply.call(@leader, payload)).to eq(:duplicate)
    expect(score.reload.points).to eq(5)
    expect(@leader.transaction_log_entries.pluck(:action)).to include('match.player_score_applied', 'match_score.updated')
    expect(@leader.transaction_log_entries.find_by!(action: 'match_score.updated').metadata['changes']['points']).to eq('from' => 7,
                                                                                                                        'to' => 5)
  end

  it 'lets an admin correction win before polling, even against a fresh fabricated revision' do
    payload = agree.locked_payload.deep_stringify_keys
    score = @match.match_scores.first
    patch "/match_scores/#{score.id}", params: { points: 5 }, headers: @leader.owner.create_new_auth_token, as: :json
    payload['base_score_revision'] = @match.reload.score_revision
    expect(PlayerScoreProposalApply.call(@leader, payload)).to eq(:rejected_admin_override)
    expect(score.reload.points).to eq(5)
  end
end
