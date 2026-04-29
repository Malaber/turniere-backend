# frozen_string_literal: true

class BetsController < ApplicationController
  before_action :set_match, only: %i[index create]
  before_action :authenticate_user!, only: %i[create]
  before_action -> { require_writable_tournament!(@match.tournament) }, only: %i[create]
  rescue_from UserServiceError, with: :handle_user_service_error

  def index
    render json: @match.bets, serializer: BetsSerializer
  end

  def create
    render json: user_service.bet!(@match, Team.find_by(id: params[:team]))
  end

  private

  def user_service
    @user_service ||= UserService.new current_user
  end

  def set_match
    @match = Match.find params[:match_id]
  end

  def handle_user_service_error(exception)
    render json: { error: exception.message }, status: :unprocessable_content
  end
end
