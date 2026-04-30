# frozen_string_literal: true

class StagesController < ApplicationController
  before_action :set_stage, only: %i[show update]
  before_action :authenticate_user!, only: %i[update]
  before_action -> { require_owner! @stage.owner }, only: %i[update]
  before_action -> { require_writable_tournament!(@stage.tournament) }, only: %i[update]

  # GET /stages/1
  def show
    render json: @stage, include: '**'
  end

  # PUT /stages/1
  def update
    return render_invalid_stage_state unless stage_params[:state] == 'finished'
    return render_stage_not_running unless @stage.in_progress?

    finish_group_stage
  end

  private

  def finish_group_stage
    synced_tournament = nil
    @playoff_start_failure = nil
    @transaction_log_advancing_teams = []

    Stage.transaction do
      synced_tournament = finish_group_stage_inside_transaction
    end
    record_playoff_start_failure if @playoff_start_failure
    push_sync_if_needed!(synced_tournament) unless synced_tournament.nil?
    TournamentLiveBroadcast.call(synced_tournament.id) unless synced_tournament.nil?
  end

  def finish_group_stage_inside_transaction
    TournamentTransactionLogger.lock_tournament!(@stage.tournament)
    @stage.reload
    return unless stage_running_for_playoff_start?
    return unless group_stage_over_for_playoff_start?
    return unless recalculate_group_scores_for_playoff_start
    return unless no_blocking_ties_for_playoff_start?

    start_playoffs_inside_transaction
  end

  def start_playoffs_inside_transaction
    @transaction_log_advancing_teams = GroupStageService.get_advancing_teams(@stage)
    if @stage.update(stage_params) &&
       AddPlayoffsToTournamentAndSave.call(tournament: @stage.tournament,
                                           teams: @transaction_log_advancing_teams).success?
      record_playoffs_started
      render json: @stage
      return @stage.tournament
    elsif @stage.errors.any?
      render json: @stage.errors, status: :unprocessable_content
      raise ActiveRecord::Rollback
    end

    @playoff_start_failure = { reason: 'generation_failed', blocking_ties: [] }
    render json: { error: 'Generating group stage failed' }, status: :unprocessable_content
    raise ActiveRecord::Rollback
  end

  def render_invalid_stage_state
    render json: {
      error: 'The state attribute may only be changed to finished'
    }, status: :unprocessable_content
  end

  def render_stage_not_running
    render json: { error: 'Only running group stages can be finished' }, status: :unprocessable_content
  end

  def stage_running_for_playoff_start?
    return true if @stage.in_progress?

    render_stage_not_running
    false
  end

  def group_stage_over_for_playoff_start?
    return true if @stage.over?

    render_playoff_start_failure(reason: 'unfinished_matches')
    false
  end

  def recalculate_group_scores_for_playoff_start
    @stage.groups.each do |group|
      next if UpdateGroupsGroupScoresAndSave.call(group: group).success?

      render json: { error: 'Updating group scores failed' }, status: :unprocessable_content
      raise ActiveRecord::Rollback
    end

    true
  end

  def no_blocking_ties_for_playoff_start?
    blocking_ties = GroupStageService.blocking_ties_for(@stage)
    return true if blocking_ties.empty?

    render_playoff_start_failure(reason: 'decider_missing', blocking_ties: blocking_ties)
    false
  end

  def render_playoff_start_failure(reason:, blocking_ties: [])
    TournamentTransactionLogger.record_playoffs_start_failed!(
      stage: @stage,
      user: current_user,
      reason: reason,
      blocking_ties: blocking_ties
    )
    render json: playoff_start_failure_payload(reason, blocking_ties), status: :unprocessable_content
    nil
  end

  def playoff_start_failure_payload(reason, blocking_ties)
    if reason == 'unfinished_matches'
      return {
        error: 'Group Stage still has some matches that are not over yet. Finish them to generate playoffs'
      }
    end

    {
      error: 'Playoffs cannot be generated yet because a decider match is required for an advancing place',
      blocking_ties: blocking_ties
    }
  end

  def record_playoffs_started
    TournamentTransactionLogger.record_playoffs_started!(
      stage: @stage,
      user: current_user,
      advancing_teams: @transaction_log_advancing_teams
    )
  end

  def record_playoff_start_failure
    TournamentTransactionLogger.record_playoffs_start_failed!(
      stage: @stage,
      user: current_user,
      reason: @playoff_start_failure.fetch(:reason),
      blocking_ties: @playoff_start_failure.fetch(:blocking_ties)
    )
  end

  def set_stage
    @stage = Stage.find(params[:id])
  end

  def stage_params
    params.slice(:state).permit!
  end

  def push_sync_if_needed!(tournament)
    TournamentSyncEnqueue.call(tournament)
  end
end
