# frozen_string_literal: true

class TeamActionListsController < ApplicationController
  before_action :set_tournament
  before_action :authenticate_user!, only: %i[update_item]
  before_action -> { require_owner! @tournament.owner }, only: %i[update_item]
  before_action -> { require_writable_tournament!(@tournament) }, only: %i[update_item]
  before_action :set_team_action_item, only: %i[update_item]

  # PATCH /tournaments/:tournament_id/team_action_lists/:key/teams/:team_id
  def update_item
    if @team_action_item.update(team_action_item_params)
      push_sync_if_needed!(@tournament)
      render json: @team_action_item
    else
      render json: @team_action_item.errors, status: :unprocessable_entity
    end
  end

  private

  def set_tournament
    @tournament = Tournament.find(params[:tournament_id])
  end

  def set_team_action_item
    list = @tournament.team_action_lists.find_by!(key: params[:key])
    @team_action_item = list.team_action_items.find_by!(team_id: params[:team_id])
  end

  def team_action_item_params
    params.slice(:completed).permit(:completed)
  end

  def push_sync_if_needed!(tournament)
    TournamentSyncEnqueue.call(tournament)
  end
end
