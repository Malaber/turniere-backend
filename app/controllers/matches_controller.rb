# frozen_string_literal: true

class MatchesController < ApplicationController
  before_action :set_match, only: %i[show update swap]
  before_action :set_group, only: %i[create]
  before_action :validate_params, only: %i[update]
  before_action :set_swap_target, only: %i[swap]
  before_action -> { require_owner! @match.owner }, only: %i[update swap]
  before_action -> { require_owner! @group.owner }, only: %i[create]
  before_action :set_tournament, only: %i[index metadata]
  before_action -> { require_owner! @tournament.owner }, only: %i[metadata]
  before_action -> { require_writable_tournament!(@match.tournament) }, only: %i[update swap]
  before_action -> { require_writable_tournament!(@group.tournament) }, only: %i[create]
  before_action -> { require_writable_tournament!(@tournament) }, only: %i[metadata]

  # GET/tournaments/1/matches
  def index
    render json: TournamentMatchesPayload.build(@tournament, match_index_params)
  end

  # GET /matches/1
  def show
    render json: @match, include: %w[match_scores.points match_scores.team bets]
  end

  # POST /groups/:group_id/matches
  def create
    match = nil
    synced_tournament = nil

    Match.transaction do
      TournamentTransactionLogger.lock_tournament!(@group.tournament)
      match = build_decider_match

      if match.errors.any?
        render json: match.errors, status: :unprocessable_content
        raise ActiveRecord::Rollback
      elsif match.save
        UpdateGroupsGroupScoresAndSave.call(group: @group)
        group_scores = group_scores_for_log(@group)
        TournamentTransactionLogger.record_decider_match_created!(match: match, user: current_user, group_scores: group_scores)
        synced_tournament = @group.tournament
        render json: match, include: %w[match_scores.team group], status: :created
      else
        render json: match.errors, status: :unprocessable_content
        raise ActiveRecord::Rollback
      end
    end

    push_sync_if_needed!(synced_tournament) unless synced_tournament.nil?
    TournamentLiveBroadcast.call(synced_tournament.id) unless synced_tournament.nil?
  end

  # PATCH/PUT /matches/1
  def update
    new_state = match_params['state']
    synced_tournament = nil
    @transaction_log_group_scores = []
    @transaction_log_advanced_match_ids = []

    Match.transaction do
      synced_tournament = update_match_inside_transaction(new_state)
    end
    push_sync_if_needed!(synced_tournament) unless synced_tournament.nil?
    TournamentLiveBroadcast.call(synced_tournament.id) unless synced_tournament.nil?
  end

  # PATCH /tournaments/1/matches/metadata
  def metadata
    attrs = match_metadata_params
    if attrs.empty?
      render json: { error: 'At least one metadata field is required' }, status: :bad_request
      return
    end

    matches = bulk_metadata_matches
    return if performed?

    Match.transaction do
      TournamentTransactionLogger.lock_tournament!(@tournament)
      @tournament.reload
      matches.each { |match| match.update!(attrs) }
    end

    render json: matches.map(&:reload), each_serializer: LiveMatchSerializer, include: %w[match_scores.team]
    push_sync_if_needed!(@tournament)
    TournamentLiveBroadcast.call(@tournament.id)
  end

  # PATCH /matches/1/swap
  def swap
    unless @match.swappable_with?(@swap_target)
      render json: { error: 'Matches must be different group matches from the same group' }, status: :unprocessable_content
      return
    end

    synced_tournament = nil

    Match.transaction do
      source_position = @match.position
      target_position = @swap_target.position

      @match.update!(position: target_position)
      @swap_target.update!(position: source_position)

      synced_tournament = @match.tournament
    end

    swapped_matches = Match.where(id: [@match.id, @swap_target.id]).order(:position)
    render json: swapped_matches, each_serializer: ExtendedMatchSerializer, include: %w[match_scores.team bets stage group]
    push_sync_if_needed!(synced_tournament)
    TournamentLiveBroadcast.call(synced_tournament.id)
  end

  private

  def handle_match_end
    if @match.group_match?
      group = @match.group
      unless UpdateGroupsGroupScoresAndSave.call(group: group).success?
        logger.warn "Updating groups group score failed for #{group}"
      end
      @transaction_log_group_scores = group_scores_for_log(group)
      return
    end

    if @match.winner.nil?
      render json: { error: 'Stopping undecided Matches isn\'t allowed in playoff stage' },
             status: :unprocessable_content
      raise ActiveRecord::Rollback
    end

    result = PopulateMatchBelowAndSave.call(match: @match)
    if result.success?
      @transaction_log_advanced_match_ids = advanced_match_ids_for(result)
      return
    end

    render json: { error: 'Moving Team one stage down failed' },
           status: :unprocessable_content
    raise ActiveRecord::Rollback
  end

  def handle_match_stop
    @match.match_scores.each do |match_score|
      match_score.update!(points: 0, hidden_points: 0)
    end
  end

  def update_group_scores
    group = @match.group
    if UpdateGroupsGroupScoresAndSave.call(group: group).success?
      @transaction_log_group_scores = group_scores_for_log(group)
      return
    end

    logger.warn "Updating groups group score failed for #{group}"
  end

  def update_match_inside_transaction(new_state)
    tournament = @match.tournament
    TournamentTransactionLogger.lock_tournament!(tournament)
    @match.reload
    validate_transition_inside_transaction(new_state)

    old_state = @match.state
    if @match.update(match_params)
      record_successful_match_update(old_state, new_state) unless new_state.nil?
      render json: @match
      tournament
    else
      render json: @match.errors, status: :unprocessable_content
      raise ActiveRecord::Rollback
    end
  end

  def validate_transition_inside_transaction(new_state)
    return if new_state.nil?

    transition_error = match_transition_error(@match, new_state)
    return if transition_error.nil?

    render json: { error: transition_error }, status: :unprocessable_content
    raise ActiveRecord::Rollback
  end

  def record_successful_match_update(old_state, new_state)
    handle_match_end if new_state == 'finished'
    handle_match_stop if new_state == 'not_started'
    update_group_scores if @match.group_match? && %w[in_progress not_started].include?(new_state)
    TournamentTransactionLogger.record_match_state_change!(
      match: @match,
      user: current_user,
      old_state: old_state,
      new_state: new_state,
      details: {
        group_scores: @transaction_log_group_scores,
        advanced_match_ids: @transaction_log_advanced_match_ids
      }
    )
  end

  def validate_params
    return unless params.key?(:state)

    transition_error = match_transition_error(@match, match_params['state'])
    return if transition_error.nil?

    render json: { error: transition_error }, status: :unprocessable_content
  end

  def set_match
    @match = Match.find(params[:id])
  end

  def set_tournament
    @tournament = Tournament.find(params[:tournament_id])
  end

  def set_swap_target
    @swap_target = Match.find_by(id: params[:other_match_id])
    return unless @swap_target.nil?

    render json: { error: 'Match not found' }, status: :not_found
  end

  def set_group
    @group = Group.find(params[:group_id])
  end

  def match_params
    params.slice(:state, :location, :start_time, :notes).permit!
  end

  def match_index_params
    params.slice(:state, :stage_id, :stage_level, :position, :group_stage_position).permit!
  end

  def match_metadata_params
    params.slice(:location, :start_time, :notes).permit!
  end

  def bulk_metadata_matches
    return bulk_metadata_matches_by_id if params.key?(:match_ids)

    return @tournament.matches if ActiveModel::Type::Boolean.new.cast(params[:all])
    return filtered_bulk_metadata_matches if match_index_params.values.any?(&:present?)

    render json: { error: 'Select matches with match_ids, filters, or all=true' }, status: :bad_request
    []
  end

  def bulk_metadata_matches_by_id
    ids = parse_match_ids
    return [] if performed?

    matches = @tournament.matches.select { |match| ids.include?(match.id) }
    missing_ids = ids - matches.map(&:id)
    if missing_ids.any?
      render json: { error: "Matches not found in tournament: #{missing_ids.join(', ')}" }, status: :not_found
      return []
    end

    ids.map { |id| matches.find { |match| match.id == id } }
  end

  def filtered_bulk_metadata_matches
    TournamentMatchesPayload.matches_for(@tournament, match_index_params)
  end

  def parse_match_ids
    Array(params[:match_ids]).map { |id| Integer(id.to_s, 10) }.uniq
  rescue ArgumentError, TypeError
    render json: { error: 'match_ids must contain only integer ids' }, status: :bad_request
    []
  end

  def create_match_params
    params.slice(:team_ids).permit(team_ids: [])
  end

  def build_decider_match
    team_ids = create_match_params[:team_ids].to_a.map(&:to_i).uniq
    teams = @group.teams.select { |team| team_ids.include?(team.id) }

    Match.new(
      group: @group,
      state: :not_started,
      position: (@group.matches.maximum(:position) || -1) + 1,
      decider: true,
      match_scores: teams.map { |team| MatchScore.new(team: team) }
    ).tap do |match|
      if team_ids.size != 2 || teams.size != 2
        match.errors.add(:team_ids, 'must contain exactly two teams from this group')
      end
    end
  end

  def match_transition_error(match, new_state)
    case new_state
    when 'in_progress'
      'Match can\'t start in this state' unless match.not_started?
    when 'finished'
      'Match can\'t finish in this state' unless match.in_progress?
    when 'not_started'
      'Match can\'t stop in this state' unless match.in_progress?
    else
      'Invalid target state'
    end
  end

  def group_scores_for_log(group)
    group.group_scores.includes(:team).reload
  end

  def advanced_match_ids_for(result)
    Array(result.object_to_save).flatten.grep(Match).reject { |match| match.id == @match.id }.map(&:id)
  end

  def push_sync_if_needed!(tournament)
    TournamentSyncEnqueue.call(tournament)
  end
end
