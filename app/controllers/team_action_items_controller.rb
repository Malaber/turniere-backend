# frozen_string_literal: true

class TeamActionItemsController < ApplicationController
  before_action :set_team_action_item, only: %i[update]
  before_action :authenticate_user!, only: %i[update]
  before_action -> { require_owner! @team_action_item.owner }, only: %i[update]
  before_action -> { require_writable_tournament!(@team_action_item.tournament) }, only: %i[update]
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found_error

  # PATCH /team_action_items/1
  def update
    if TeamActionItemUpdate.call(
      team_action_item: @team_action_item,
      completed: team_action_item_params.fetch(:completed)
    )
      render json: @team_action_item
    else
      render json: @team_action_item.errors, status: :unprocessable_content
    end
  end

  private

  def set_team_action_item
    @team_action_item = TeamActionItem.find(params[:id])
  end

  def team_action_item_params
    params.slice(:completed).permit(:completed)
  end
end
