# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :set_account, only: %i[show]

  def show
    render json: @account, serializer: AccountProfileSerializer, scope: current_user
  end

  private

  def set_account
    @account = User.includes(:tournaments, player_teams: :tournament).find(params[:id])
  end
end
