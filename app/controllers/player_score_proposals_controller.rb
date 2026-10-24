# frozen_string_literal: true

class PlayerScoreProposalsController < ApplicationController
  before_action :authenticate_user!, only: %i[show update matches]
  rescue_from PlayerScoreProposalService::Forbidden do |error|
    render json: { error: error.message }, status: :forbidden
  end
  rescue_from PlayerScoreProposalService::Conflict do |error|
    render json: { error: error.message }, status: :conflict
  end
  rescue_from PlayerScoreProposalService::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_content
  end

  def matches
    tournament = Tournament.find(params[:id])
    raise PlayerScoreProposalService::Forbidden, 'Player proposals require a follower' unless tournament.sync_accepts_push?

    eligible = tournament.matches.select do |match|
      match.in_progress? && PlayerScoreProposalService.eligible_team_ids(match, current_user).any?
    end
    render json: { matches: eligible.map { |match| player_payload(match) } }
  end

  def show
    match = Match.find(params[:match_id])
    authorize_player!(match)
    render json: player_payload(match)
  end

  def update
    match = Match.find(params[:match_id])
    scores = params.require(:scores)
    raise PlayerScoreProposalService::Invalid, 'Scores must be an object' unless scores.is_a?(ActionController::Parameters)

    PlayerScoreProposalService.submit!(match: match, user: current_user, team_id: params[:team_id],
                                       scores: scores.to_unsafe_h)
    render json: player_payload(match.reload)
  end

  # Read-only capability for the leader. No acknowledgements or inbound commands.
  def index
    tournament = Tournament.find(params[:id])
    token = request.headers['Authorization'].to_s.delete_prefix('Bearer ')
    unless tournament.sync_accepts_push? && tournament.sync_token_matches?(token)
      return render json: { error: 'Invalid proposal polling token' }, status: :unauthorized
    end

    after = Integer(params.fetch(:after, '0').to_s, 10)
    proposals = PlayerScoreProposal.where(tournament: tournament).where('locked_sequence > ?', after)
                                   .order(:locked_sequence).limit(100)
    render json: { proposals: proposals.map(&:locked_payload) }
  rescue ArgumentError
    render json: { error: 'Invalid cursor' }, status: :bad_request
  end

  private

  def authorize_player!(match)
    raise PlayerScoreProposalService::Forbidden, 'You must belong to a participating team' if PlayerScoreProposalService.eligible_team_ids(
      match, current_user
    ).empty?
  end

  def player_payload(match)
    authorize_player!(match)
    proposal = PlayerScoreProposal.find_by(tournament: match.tournament, source_match_id: match.sync_source_id)
    teams = match.teams
    proposals = (proposal&.team_proposals || {}).filter_map do |source_id, value|
      team = teams.find { |candidate| candidate.sync_source_id.to_s == source_id }
      next if team.nil?

      { team_id: team.id, scores: teams.to_h { |candidate| [candidate.id, value['scores'][candidate.sync_source_id.to_s]] } }
    end
    {
      match_id: match.id,
      official_scores: match.match_scores.to_h { |score| [score.team_id, match.decider? ? score.hidden_points : score.points] },
      eligible_team_ids: PlayerScoreProposalService.eligible_team_ids(match, current_user),
      accepting: match.tournament.sync_accepts_push? && match.in_progress? &&
        !match.player_score_blocked? && !proposal&.locked_at?,
      locked: proposal&.locked_at? || false, revision: proposal&.revision || 0,
      proposals: proposals, teams: teams.map { |team| { id: team.id, name: team.name } }
    }
  end
end
