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
  before_action :set_tournament,
                only: %i[update destroy set_timer timer sync_state test_sync start_next_group_matches]
  before_action :authenticate_user!, only: %i[create update destroy set_timer test_sync start_next_group_matches]
  before_action -> { require_owner! @tournament.owner },
                only: %i[update destroy set_timer test_sync start_next_group_matches]
  before_action :validate_create_params, only: %i[create]
  before_action :validate_update_params, only: %i[update]
  before_action :validate_set_timer_params, only: %i[set_timer]
  before_action :ensure_update_allowed!, only: %i[update]
  before_action :ensure_destroy_allowed!, only: %i[destroy]
  before_action :ensure_timer_update_allowed!, only: %i[set_timer]
  before_action -> { require_writable_tournament!(@tournament) }, only: %i[start_next_group_matches]
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
        TournamentPayload.build(@tournament, scope: current_user)
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
        TournamentTransactionLogger.record_tournament_created!(tournament: tournament, user: current_user)
        render json: tournament, status: :created, location: tournament
      else
        render json: tournament.errors, status: :unprocessable_content
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
      render json: tournament.errors, status: :unprocessable_content
      return
    end
    # return appropriate result
    if result.success?
      TournamentTransactionLogger.record_tournament_created!(tournament: result.tournament, user: current_user)
      render json: result.tournament, status: :created, location: result.tournament
    else
      render json: { error: 'Tournament generation failed' }, status: :unprocessable_content
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
        render json: @tournament.errors, status: :unprocessable_content
        raise ActiveRecord::Rollback
      end
    end
    push_sync_if_needed!(synced_tournament) unless synced_tournament.nil?
  end

  # DELETE /tournaments/1
  def destroy
    @tournament.destroy
  end

  # GET /tournaments/:id/timer
  def timer
    render json: serialize_timer_state(@tournament)
  end

  # PATCH /tournaments/:id/timer
  def set_timer
    synced_tournament = nil

    Tournament.transaction do
      TournamentTransactionLogger.lock_tournament!(@tournament)
      @tournament.reload
      old_timer = serialize_timer_state(@tournament)

      if @tournament.update(timer_params)
        TournamentTransactionLogger.record_timer_changed!(
          tournament: @tournament,
          user: current_user,
          old_timer: old_timer,
          new_timer: serialize_timer_state(@tournament)
        )
        synced_tournament = @tournament
        render json: @tournament
      else
        render json: @tournament.errors, status: :unprocessable_content
        raise ActiveRecord::Rollback
      end
    end

    push_sync_if_needed!(synced_tournament) unless synced_tournament.nil?
  end

  def sync_state
    TournamentSnapshotImporter.import!(tournament: @tournament, snapshot: sync_state_params)
    TournamentLiveBroadcast.call(@tournament.id)
    render json: @tournament, include: '**'
  rescue KeyError, ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def test_sync
    unless @tournament.sync_push_enabled?
      return render json: {
        error: 'Tournament sync test requires writable tournament with sync_target_url and sync_auth_token'
      }, status: :unprocessable_content
    end

    TournamentSyncPusher.push!(@tournament)
    render json: @tournament.reload, include: '**'
  rescue TournamentSyncPusher::SyncFailed => e
    @tournament.reload
    render json: {
      error: e.message,
      tournament: TournamentSerializer.new(@tournament, scope: current_user).as_json
    }, status: :bad_gateway
  end

  # PATCH /tournaments/:id/start_next_group_matches
  def start_next_group_matches
    started_matches = TournamentGroupMatchStarter.start_next!(@tournament, logger:, user: current_user)
    if started_matches.any?
      push_sync_if_needed!(@tournament)
      TournamentLiveBroadcast.call(@tournament.id)
    end

    render json: ActiveModelSerializers::SerializableResource.new(
      started_matches,
      each_serializer: LiveMatchSerializer,
      include: %w[match_scores.team]
    ).as_json
  end

  private

  def timer_params
    {
      timestamp: params[:timestamp],
      timer_mode: params[:timer_mode],
      timer_reason: params[:timer_reason],
      timer_reason_text: params[:timer_reason_text]
    }
  end

  def serialize_timer_state(tournament)
    {
      timestamp: tournament.timestamp&.iso8601,
      timer_mode: tournament.timer_mode,
      timer_reason: tournament.timer_reason,
      timer_reason_text: tournament.timer_reason_text
    }
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
      :location, :starts_at, :ends_at, :website_url,
      :read_only_mode, :sync_target_url, :sync_auth_token
    ).permit!
  end

  def validate_create_params
    return if ActiveModel::Type::Boolean.new.cast(params[:read_only_mode])

    teams = params['teams']
    return if teams.is_a?(Array) && teams.reject { |t| t.is_a? ActionController::Parameters }.count.zero?

    render json: { error: 'Invalid teams array' }, status: :unprocessable_content
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
    }, status: :unprocessable_content
  end
  def sync_state_params
    params.require(:snapshot).permit!.to_h
  end

  def authorize_sync_request!
    return render json: { error: 'Tournament is not configured to accept sync pushes' }, status: :unprocessable_content unless @tournament.sync_accepts_push?

    token = request.authorization.to_s.delete_prefix('Bearer ').presence || request.headers['X-Tournament-Sync-Token'].to_s
    return render json: { error: 'Missing sync token' }, status: :unauthorized if token.blank?

    return if @tournament.sync_token_matches?(token)

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

  def validate_set_timer_params
    timestamp = params[:timestamp]
    timestamp_seconds = params[:timestamp_seconds]
    timer_mode = params[:timer_mode]
    normalize_timer_reason_params
    timer_reason = params[:timer_reason]
    timer_reason_text = params[:timer_reason_text]
    clear_timer = ActiveModel::Type::Boolean.new.cast(params[:clear_timer])

    if clear_timer
      return validate_clear_timer_params(timestamp, timestamp_seconds, timer_mode, timer_reason, timer_reason_text)
    end

    if timer_mode.present? && !Tournament::TIMER_MODES.include?(timer_mode)
      return render_timer_validation_error('Invalid timer_mode')
    end

    timer_reason_error = validate_timer_reason_params(timer_reason, timer_reason_text)
    return render_timer_validation_error(timer_reason_error) if timer_reason_error

    # throw error if both timestamp and timestamp_seconds are present
    if timestamp.present? && timestamp_seconds.present?
      return render_timer_validation_error('Only one of timestamp or timestamp_seconds is allowed')
    end

    if timer_mode == 'countup' && timestamp_seconds.present?
      return render_timer_validation_error('timestamp_seconds is only allowed for countdown mode')
    end

    if timestamp_seconds.present?
      begin
        timestamp_seconds = Integer(timestamp_seconds)
      rescue ArgumentError
        return render_timer_validation_error('Invalid seconds format')
      end

      if timestamp_seconds <= 0
        return render_timer_validation_error('Timestamp must be in the future for countdown mode')
      end

      parsed_time = Time.zone.now + timestamp_seconds
      params[:timestamp] = parsed_time
      params[:timer_mode] = 'countdown'
    elsif timestamp.present?
      begin
        parsed_time = Time.zone.parse(timestamp)
        if parsed_time.nil?
          return render_timer_validation_error('Invalid timestamp format')
        elsif timer_mode != 'countup' && !parsed_time.future?
          return render_timer_validation_error('Timestamp must be in the future for countdown mode')
        end

        params[:timestamp] = parsed_time
        params[:timer_mode] = timer_mode.presence || 'countdown'
      rescue ArgumentError
        return render_timer_validation_error('Invalid timestamp format')
      end
    elsif timer_mode == 'countup'
      params[:timestamp] = Time.zone.now
    elsif timer_mode.present?
      return render_timer_validation_error('timer_mode requires timestamp, timestamp_seconds, or clear_timer')
    else
      return render_timer_validation_error('timestamp, timestamp_seconds, or clear_timer is required')
    end
  end

  def normalize_timer_reason_params
    params[:timer_reason] = params[:timer_reason].presence
    params[:timer_reason_text] = timer_reason_text_param
  end

  def timer_reason_text_param
    return nil unless params.key?(:timer_reason_text)

    params[:timer_reason_text].to_s.strip.presence
  end

  def validate_clear_timer_params(timestamp, timestamp_seconds, timer_mode, timer_reason, timer_reason_text)
    if timestamp.present? || timestamp_seconds.present? || timer_mode.present? ||
       timer_reason.present? || timer_reason_text.present?
      return render_timer_validation_error('clear_timer cannot be combined with timer values or timer reason')
    end

    params[:timestamp] = nil
    params[:timer_mode] = nil
    params[:timer_reason] = nil
    params[:timer_reason_text] = nil
  end

  def validate_timer_reason_params(timer_reason, timer_reason_text)
    return if timer_reason.blank? && timer_reason_text.blank?
    return 'timer_reason_text is only allowed when timer_reason is custom' if timer_reason.blank?
    return 'Invalid timer_reason' unless Tournament::TIMER_REASONS.include?(timer_reason)

    if timer_reason == 'custom' && timer_reason_text.blank?
      return 'timer_reason_text is required for custom timer_reason'
    end

    return unless timer_reason != 'custom' && timer_reason_text.present?

    'timer_reason_text is only allowed when timer_reason is custom'
  end

  def render_timer_validation_error(message)
    render json: { error: message }, status: :unprocessable_content
  end
end
