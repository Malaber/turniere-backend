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
    Team.transaction do
      @team.assign_attributes(team_params)
      assign_players_from_params if player_assignment_requested?
      raise ActiveRecord::Rollback if performed?

      @team.save!
    end
    return if performed?

    push_sync_if_needed!(@team.tournament)
    render json: @team
  rescue ActiveRecord::RecordInvalid => e
    render json: e.record.errors, status: :unprocessable_content
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.slice(:name).permit!
  end

  def player_assignment_requested?
    params.key?(:player_email) || params.key?(:player_id) ||
      params.key?(:player_emails) || params.key?(:player_ids)
  end

  def assign_players_from_params
    unless tournament_owner?
      render_forbidden_error
      return
    end

    if params.key?(:player_emails)
      @team.players = players_from_emails(params[:player_emails])
    elsif params.key?(:player_ids)
      @team.players = players_from_ids(params[:player_ids])
    elsif params.key?(:player_email)
      add_or_clear_player_from_email
    else
      add_or_clear_player_from_id
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: e.record.errors, status: :unprocessable_content
  end

  def players_from_emails(emails)
    email_values(emails).map { |email| User.find_or_create_player_by_email!(email) }
  end

  def players_from_ids(player_ids)
    id_values = Array.wrap(player_ids).map(&:to_s).map(&:strip).reject(&:blank?)
    return [] if id_values.empty?

    User.where(id: id_values).tap do |players|
      raise ActiveRecord::RecordNotFound.new('Could not find all players', 'User') unless players.size == id_values.uniq.size
    end
  end

  def add_or_clear_player_from_email
    email = params[:player_email].to_s.strip
    if email.blank?
      @team.players = []
      return
    end

    add_player(User.find_or_create_player_by_email!(email))
  end

  def add_or_clear_player_from_id
    player_id = params[:player_id].to_s.strip
    if player_id.blank?
      @team.players = []
      return
    end

    add_player(User.find(player_id))
  end

  def add_player(player)
    @team.players << player unless @team.player_ids.include?(player.id)
  end

  def email_values(emails)
    Array.wrap(emails).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def require_team_update_actor!
    return if tournament_owner? || @team.players.include?(current_user)

    render_forbidden_error
  end

  def tournament_owner?
    @team.owner == current_user
  end

  def push_sync_if_needed!(tournament)
    TournamentSyncEnqueue.call(tournament)
  end
end
