# frozen_string_literal: true

class MatchScoresController < ApplicationController
  before_action :set_match_score, only: %i[show update]
  before_action :authenticate_user!, only: %i[update]
  before_action -> { require_owner! @match_score.owner }, only: %i[update]
  before_action -> { require_writable_tournament!(@match_score.tournament) }, only: %i[update]

  # GET /scores/1
  def show
    render json: @match_score
  end

  # PATCH/PUT /scores/1
  def update
    synced_tournament = nil

    MatchScore.transaction do
      tournament = @match_score.tournament
      TournamentTransactionLogger.lock_tournament!(tournament)
      @match_score.reload
      old_values = score_values(@match_score)

      if @match_score.update(match_score_params)
        match = @match_score.match.reload
        match.update!(player_score_blocked: true, score_revision: match.score_revision + 1)
        group_scores = []
        if @match_score.part_of_group_match?
          UpdateGroupsGroupScoresAndSave.call(group: @match_score.match.group)
          group_scores = group_scores_for_log(@match_score.match.group)
        end
        TournamentTransactionLogger.record_match_score_update!(
          match_score: @match_score,
          user: current_user,
          changes: score_changes(old_values, @match_score),
          group_scores: group_scores
        )
        synced_tournament = tournament
        render json: @match_score
      else
        render json: @match_score.errors, status: :unprocessable_content
        raise ActiveRecord::Rollback
      end
    end

    return if synced_tournament.nil?

    push_sync_if_needed!(synced_tournament)
    TournamentLiveBroadcast.call(synced_tournament.id)
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_match_score
    @match_score = MatchScore.find(params[:id])
  end

  # Only allow a trusted parameter "white list" through.
  def match_score_params
    params.slice(:points, :hidden_points).permit!
  end

  def score_values(match_score)
    {
      points: match_score.points,
      hidden_points: match_score.hidden_points
    }
  end

  def score_changes(old_values, match_score)
    permitted_params = match_score_params
    score_values(match_score).each_with_object({}) do |(field, new_value), changes|
      next unless permitted_params.key?(field) || permitted_params.key?(field.to_s)
      next if old_values[field] == new_value

      changes[field] = {
        from: old_values[field],
        to: new_value
      }
    end
  end

  def group_scores_for_log(group)
    group.group_scores.includes(:team).reload
  end

  def push_sync_if_needed!(tournament)
    TournamentSyncEnqueue.call(tournament)
  end
end
