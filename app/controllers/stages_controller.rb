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
    if stage_params[:state] == 'finished'
      unless @stage.state == 'in_progress'
        render json: { error: 'Only running group stages can be finished' }, status: :unprocessable_entity
        return
      end

      synced_tournament = nil
      Stage.transaction do
        if @stage.update(stage_params)
          handle_group_stage_end

          render json: @stage
          synced_tournament = @stage.tournament
        else
          render json: @stage.errors, status: :unprocessable_entity
          raise ActiveRecord::Rollback
        end
      end
      push_sync_if_needed!(synced_tournament) unless synced_tournament.nil?
    else
      render json: {
        error: 'The state attribute may only be changed to finished'
      }, status: :unprocessable_entity
    end
  end

  private

  def handle_group_stage_end
    unless @stage.over?
      render json: {
        error: 'Group Stage still has some matches that are not over yet. Finish them to generate playoffs'
      }, status: :unprocessable_entity
      raise ActiveRecord::Rollback
    end

    @stage.groups.each do |group|
      next if UpdateGroupsGroupScoresAndSave.call(group: group).success?

      render json: { error: 'Updating group scores failed' }, status: :unprocessable_entity
      raise ActiveRecord::Rollback
    end

    blocking_ties = GroupStageService.blocking_ties_for(@stage)
    if blocking_ties.any?
      render json: {
        error: 'Playoffs cannot be generated yet because a decider match is required for an advancing place',
        blocking_ties: blocking_ties
      }, status: :unprocessable_entity
      raise ActiveRecord::Rollback
    end

    return unless AddPlayoffsToTournamentAndSave.call(tournament: @stage.tournament,
                                                      teams: GroupStageService.get_advancing_teams(@stage)).success?

    TeamActionListService.ensure_group_stage_survivor_playoff_token_list!(@stage.tournament)
    return

    render json: { error: 'Generating group stage failed' }, status: :unprocessable_entity
    raise ActiveRecord::Rollback
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
