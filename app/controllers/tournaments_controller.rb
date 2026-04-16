# frozen_string_literal: true

class TournamentsController < ApplicationController
  class NoOpRequestProfiling
    def measure(_name)
      yield
    end

    def apply_to(_response, label:)
      label
    end
  end

  before_action :set_tournament_for_show, only: %i[show]
  before_action :set_tournament, only: %i[update destroy set_timer_end timer_end sync_state]
  before_action :authenticate_user!, only: %i[create update destroy set_timer_end]
  before_action -> { require_owner! @tournament.owner }, only: %i[update destroy set_timer_end]
  before_action :validate_create_params, only: %i[create]
  before_action :validate_update_params, only: %i[update]
  before_action :validate_set_timer_end_params, only: %i[set_timer_end]
  before_action :ensure_update_allowed!, only: %i[update]
  before_action :ensure_destroy_allowed!, only: %i[destroy]
  before_action :ensure_timer_update_allowed!, only: %i[set_timer_end]
  before_action :authorize_sync_request!, only: %i[sync_state]
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found_error

  # GET /tournaments
  def index
    type = index_params.fetch(:type, 'public')
    case type
    when 'public'
      tournaments = Tournament.where(public: true).order(:created_at)
    when 'private'
      tournaments = Tournament.where(owner: current_user, public: false).order(:created_at)
    else
      # invalid type specified
      render json: { error: 'invalid type' }, status: :bad_request
      return
    end
    render json: tournaments, each_serializer: SimpleTournamentSerializer
  end

  # GET /tournaments/1
  def show
    if show_params.fetch(:simple, 'false') == 'true'
      render json: @tournament, serializer: SimpleTournamentSerializer
    else
      rendered_json = @request_profiling.measure('serialize_tournament') do
        ActiveModelSerializers::SerializableResource.new(@tournament, include: '**').as_json
      end
      @request_profiling.apply_to(response, label: 'tournament.show')
      render json: rendered_json
    end
  end

  # POST /tournaments
  def create
    params = tournament_params
    group_stage = params.delete(:group_stage)
    teams = params.delete('teams')
    tournament = current_user.tournaments.new params.except(:teams, :group_stage)

    if tournament.read_only_mode?
      if tournament.save
        render json: tournament, status: :created, location: tournament
      else
        render json: tournament.errors, status: :unprocessable_entity
      end
      return
    end

    raise ActionController::ParameterMissing, :teams if teams.nil?
    if group_stage
      params.require(:playoff_teams_amount)
      groups = organize_teams_in_groups(teams)
      # add groups to tournament
      result = AddGroupStageToTournamentAndSave.call(tournament: tournament, groups: groups)
      # associate provided teams with tournament on success
      tournament.teams = groups.flatten if result.success?
    else
      # convert teams parameter into Team objects
      teams = teams.map(&method(:find_or_create_team))
      # associate provided teams with tournament
      tournament.teams = teams
      # add playoff stage to tournament
      result = AddPlayoffsToTournamentAndSave.call(tournament: tournament, teams: tournament.teams)
    end
    # validate tournament
    unless tournament.valid?
      render json: tournament.errors, status: :unprocessable_entity
      return
    end
    # return appropriate result
    if result.success?
      render json: result.tournament, status: :created, location: result.tournament
    else
      render json: { error: 'Tournament generation failed' }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /tournaments/1
  def update
    synced_tournament = nil
    Tournament.transaction do
      if only_playoff_teams_amount_changed
        @tournament.instant_finalists_amount, @tournament.intermediate_round_participants_amount =
          TournamentService.calculate_default_amount_of_teams_advancing(
            params['playoff_teams_amount'].to_i,
            @tournament.stages.find_by(level: -1).groups.size
          )
      end
      if @tournament.update(tournament_params)
        synced_tournament = @tournament
        render json: @tournament
      else
        render json: @tournament.errors, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end
    end
    push_sync_if_needed!(synced_tournament) unless synced_tournament.nil?
  end

  # DELETE /tournaments/1
  def destroy
    @tournament.destroy
  end

  # GET /tournaments/:id/timer_end
  def timer_end
    render json: { timer_end: serialize_timer_end(@tournament.timer_end) }
  end

  # PATCH /tournaments/:id/set_timer_end
  def set_timer_end
    if @tournament.update(timer_end_params)
      push_sync_if_needed!(@tournament)
      render json: @tournament
    else
      render json: @tournament.errors, status: :unprocessable_entity
    end
  end

  def sync_state
    TournamentSnapshotImporter.import!(tournament: @tournament, snapshot: sync_state_params)
    render json: @tournament, include: '**'
  rescue KeyError, ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end


  private

  def timer_end_params
    { timer_end: params[:timer_end] }
  end

  def serialize_timer_end(timer_end)
    timer_end&.iso8601
  end

  def organize_teams_in_groups(teams)
    # each team gets put into an array of teams depending on the group specified in team[:group]
    teams.group_by { |team| team['group'] }.values.map do |group|
      group.map do |team|
        find_or_create_team(team)
      end
    end
  end

  def find_or_create_team(team)
    # convert teams parameter into Team objects
    if team[:id]
      Team.find team[:id]
    elsif team[:name]
      Team.create name: team[:name]
    end
  end

  def set_tournament
    @tournament = Tournament.find(params[:id])
  end

  def set_tournament_for_show
    profiling = build_request_profiling
    @tournament = profiling.measure('load_tournament') do
      Tournament.includes(
        :user,
        :teams,
        stages: [
          { matches: { match_scores: :team } },
          { groups: [
            { matches: { match_scores: :team } },
            { group_scores: :team }
          ] }
        ]
      ).find(params[:id])
    end
    @request_profiling = profiling
  end

  def index_params
    params.permit(:type)
  end

  def show_params
    params.permit(:simple, :profile)
  end

  def profiling_requested?
    !Rails.env.production? && show_params.fetch(:profile, 'false') == 'true'
  end

  def build_request_profiling
    return NoOpRequestProfiling.new unless profiling_requested?

    require Rails.root.join('lib/local/request_profiling')
    Local::RequestProfiling.new(enabled: true)
  end

  def tournament_params
    params.slice(
      :name, :description, :public, :teams, :group_stage, :playoff_teams_amount,
      :instant_finalists_amount, :intermediate_round_participants_amount,
      :read_only_mode, :sync_target_url, :sync_auth_token
    ).permit!
  end

  def validate_create_params
    return if ActiveModel::Type::Boolean.new.cast(params[:read_only_mode])

    teams = params['teams']
    return if teams.is_a?(Array) && teams.reject { |t| t.is_a? ActionController::Parameters }.count.zero?

    render json: { error: 'Invalid teams array' }, status: :unprocessable_entity
  end

  def only_playoff_teams_amount_changed
    params['playoff_teams_amount'] &&
      params['instant_finalists_amount'].nil? &&
      params['intermediate_round_participants_amount'].nil?
  end

  def validate_update_params
    return if sync_config_only_update?

    return if only_playoff_teams_amount_changed

    playoff_teams_amount = params.key?('playoff_teams_amount') ? params['playoff_teams_amount'].to_i : @tournament.playoff_teams_amount
    instant_finalists_amount = if params.key?('instant_finalists_amount')
                                 params['instant_finalists_amount'].to_i
                               else
                                 @tournament.instant_finalists_amount
                               end
    intermediate_round_participants_amount = if params.key?('intermediate_round_participants_amount')
                                               params['intermediate_round_participants_amount'].to_i
                                             else
                                               @tournament.intermediate_round_participants_amount
                                             end

    return if instant_finalists_amount + (intermediate_round_participants_amount / 2) ==
              playoff_teams_amount

    render json: {
      error: 'playoff_teams_amount, instant_finalists_amount and intermediate_round_participants_amount don\'t match'
    }, status: :unprocessable_entity
  end
  def sync_state_params
    params.require(:snapshot).permit!.to_h
  end

  def authorize_sync_request!
    return render json: { error: 'Tournament is not configured to accept sync pushes' }, status: :unprocessable_entity unless @tournament.sync_accepts_push?

    token = request.authorization.to_s.delete_prefix('Bearer ').presence || request.headers['X-Tournament-Sync-Token'].to_s
    return render json: { error: 'Missing sync token' }, status: :unauthorized if token.blank?

    matches = token.bytesize == @tournament.sync_auth_token.to_s.bytesize &&
              ActiveSupport::SecurityUtils.secure_compare(token, @tournament.sync_auth_token.to_s)
    return if matches

    render json: { error: 'Invalid sync token' }, status: :unauthorized
  end

  def ensure_update_allowed!
    return unless @tournament.read_only_mode?
    return if sync_config_only_update?

    render_read_only_error
  end

  def ensure_destroy_allowed!
    require_writable_tournament!(@tournament)
  end

  def ensure_timer_update_allowed!
    require_writable_tournament!(@tournament)
  end

  def sync_config_only_update?
    allowed = %w[id controller action format tournament read_only_mode sync_target_url sync_auth_token]
    (params.keys - allowed).empty?
  end

  def push_sync_if_needed!(tournament)
    TournamentSyncEnqueue.call(tournament)
  end

  def validate_set_timer_end_params
    timer_end = params[:timer_end]
    timer_end_seconds = params[:timer_end_seconds]

    # throw error if both timer_end and timer_end_seconds are present
    if timer_end.present? && timer_end_seconds.present?
      return render json: { error: 'Only one of timer_end or timer_end_seconds is allowed' }, status: :unprocessable_entity
    end

    if timer_end_seconds.present?
      begin
        timer_end_seconds = Integer(timer_end_seconds)
      rescue ArgumentError
        return render json: { error: 'Invalid seconds format' }, status: :unprocessable_entity
      end

      return render json: { error: 'Timer end must be in the future' }, status: :unprocessable_entity if timer_end_seconds <= 0

      parsed_time = Time.zone.now + timer_end_seconds
      params[:timer_end] = parsed_time
    elsif timer_end.present?
      begin
        parsed_time = Time.zone.parse(timer_end)
        if parsed_time.nil?
          return render json: { error: 'Invalid datetime format' }, status: :unprocessable_entity
        elsif !parsed_time.future?
          return render json: { error: 'Timer end must be in the future' }, status: :unprocessable_entity
        end

        params[:timer_end] = parsed_time
      rescue ArgumentError
        return render json: { error: 'Invalid datetime format' }, status: :unprocessable_entity
      end
    else
      return render json: { error: 'Timer end is required' }, status: :unprocessable_entity
    end
  end
end
