# frozen_string_literal: true

class TeamActionListsController < ApplicationController
  before_action :set_tournament
  before_action :authenticate_user!, only: %i[create update_item]
  before_action -> { require_owner! @tournament.owner }, only: %i[create update_item]
  before_action -> { require_writable_tournament!(@tournament) }, only: %i[create update_item]
  before_action :set_team_action_item, only: %i[update_item]
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found_error

  # POST /tournaments/:tournament_id/team_action_lists
  def create
    team_action_list = TeamActionListService.create!(
      tournament: @tournament,
      name: team_action_list_params.fetch(:name),
      key: team_action_list_params.fetch(:key),
      action_name: team_action_list_params.fetch(:action_name),
      source: team_action_list_params.fetch(:source)
    )

    render json: team_action_list, status: :created
  rescue TeamActionListService::InvalidSourceError, TeamActionListService::EmptySourceError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: e.record.errors, status: :unprocessable_entity
  end

  # PATCH /tournaments/:tournament_id/team_action_lists/:key/teams/:team_id
  def update_item
    if TeamActionItemUpdate.call(
      team_action_item: @team_action_item,
      completed: team_action_item_params.fetch(:completed)
    )
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

  def team_action_list_params
    params.permit(:name, :key, :action_name, :source)
  end
end
