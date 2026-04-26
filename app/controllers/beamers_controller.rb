# frozen_string_literal: true

class BeamersController < ApplicationController
  before_action :set_tournament
  before_action :set_beamer, only: %i[show update destroy]
  before_action :authenticate_user!, only: %i[create update destroy]
  before_action -> { require_owner! @tournament.owner }, only: %i[create update destroy]
  before_action -> { require_writable_tournament!(@tournament) }, only: %i[create update destroy]
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found_error

  # GET /tournaments/:tournament_id/beamers
  def index
    render json: @tournament.beamers, each_serializer: BeamerSerializer
  end

  # GET /tournaments/:tournament_id/beamers/:id
  def show
    render json: @beamer
  end

  # GET /tournaments/:tournament_id/beamers/by_name?name=beamername
  def by_name
    beamer = @tournament.beamers.find_by(name: params[:name])
    beamer ||= @tournament.beamers.find_by(name: Beamer::DEFAULT_NAME)
    if beamer
      render json: beamer
    else
      render json: { error: 'No beamer found' }, status: :not_found
    end
  end

  # POST /tournaments/:tournament_id/beamers
  def create
    beamer = @tournament.beamers.new(beamer_params)
    if beamer.save
      push_sync_if_needed!
      render json: beamer, status: :created
    else
      render json: beamer.errors, status: :unprocessable_entity
    end
  end

  # PATCH /tournaments/:tournament_id/beamers/:id
  def update
    if @beamer.update(beamer_params)
      push_sync_if_needed!
      render json: @beamer
    else
      render json: @beamer.errors, status: :unprocessable_entity
    end
  end

  # DELETE /tournaments/:tournament_id/beamers/:id
  def destroy
    @beamer.destroy
    push_sync_if_needed!
    head :no_content
  end

  private

  def set_tournament
    @tournament = Tournament.find(params[:tournament_id])
  end

  def set_beamer
    @beamer = @tournament.beamers.find(params[:id])
  end

  def beamer_params
    permitted = params.permit(:name, :display_state).to_h
    config = params.key?(:config) ? params[:config] : params.dig(:beamer, :config)
    return permitted unless config

    permitted[:config] = config.respond_to?(:to_unsafe_h) ? config.to_unsafe_h : config
    permitted
  end

  def push_sync_if_needed!
    TournamentSyncEnqueue.call(@tournament)
  end
end
