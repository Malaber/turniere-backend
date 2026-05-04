# frozen_string_literal: true

class TeamsController < ApplicationController
  before_action :set_team, only: %i[show update]
  before_action :authenticate_user!, only: %i[update]
  before_action :require_team_update_actor!, only: %i[update]
  before_action -> { require_writable_tournament!(@team.tournament) }, only: %i[update]

  # GET /teams/1
  def show
    render json: @team
  end

  # PATCH/PUT /teams/1
  def update
    @team.assign_attributes(team_params)
    assign_player_from_params if player_assignment_requested?
    return if performed?

    if @team.save
      push_sync_if_needed!(@team.tournament)
      render json: @team
    else
      render json: @team.errors, status: :unprocessable_content
    end
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.slice(:name).permit!
  end

  def player_assignment_requested?
    params.key?(:player_email) || params.key?(:player_id)
  end

  def assign_player_from_params
    unless tournament_owner?
      render_forbidden_error
      return
    end

    @team.player = if params.key?(:player_email)
                     player_from_email
                   else
                     player_from_id
                   end
  rescue ActiveRecord::RecordInvalid => e
    render json: e.record.errors, status: :unprocessable_content
  end

  def player_from_email
    email = params[:player_email].to_s.strip
    return nil if email.blank?

    User.find_or_create_player_by_email!(email)
  end

  def player_from_id
    player_id = params[:player_id].to_s.strip
    return nil if player_id.blank?

    User.find(player_id)
  end

  def require_team_update_actor!
    return if tournament_owner? || @team.player == current_user

    render_forbidden_error
  end

  def tournament_owner?
    @team.owner == current_user
  end

  def push_sync_if_needed!(tournament)
    TournamentSyncEnqueue.call(tournament)
  end
end
