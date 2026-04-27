# frozen_string_literal: true

class MatchesController < ApplicationController
  before_action :set_match, only: %i[show update swap]
  before_action :set_group, only: %i[create]
  before_action :validate_params, only: %i[update]
  before_action :set_swap_target, only: %i[swap]
  before_action -> { require_owner! @match.owner }, only: %i[update swap]
  before_action -> { require_owner! @group.owner }, only: %i[create]
  before_action :set_tournament, only: %i[index]
  before_action -> { require_writable_tournament!(@match.tournament) }, only: %i[update swap]
  before_action -> { require_writable_tournament!(@group.tournament) }, only: %i[create]

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
    match = build_decider_match

    if match.errors.any?
      render json: match.errors, status: :unprocessable_entity
    elsif match.save
      UpdateGroupsGroupScoresAndSave.call(group: @group)
      push_sync_if_needed!(@group.tournament)
      TournamentLiveBroadcast.call(@group.tournament.id)
      render json: match, include: %w[match_scores.team group], status: :created
    else
      render json: match.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /matches/1
  def update
    new_state = match_params['state']
    synced_tournament = nil

    Match.transaction do
      if @match.update(match_params)
        handle_match_end if new_state == 'finished'
        if @match.group_match? && new_state == 'in_progress'
          group = @match.group
          logger.warn "Updating groups group score failed for #{group}" unless UpdateGroupsGroupScoresAndSave.call(group:).success?
        end

        render json: @match
        synced_tournament = @match.tournament
      else
        render json: @match.errors, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end
    end
    push_sync_if_needed!(synced_tournament) unless synced_tournament.nil?
    TournamentLiveBroadcast.call(synced_tournament.id) unless synced_tournament.nil?
  end

  # PATCH /matches/1/swap
  def swap
    unless @match.swappable_with?(@swap_target)
      render json: { error: 'Matches must be different group matches from the same group' },
             status: :unprocessable_entity
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
    render json: swapped_matches, each_serializer: ExtendedMatchSerializer,
           include: %w[match_scores.team bets stage group]
    push_sync_if_needed!(synced_tournament)
    TournamentLiveBroadcast.call(synced_tournament.id)
  end

  private

  def handle_match_end
    if @match.group_match?
      group = @match.group
      logger.warn "Updating groups group score failed for #{group}" unless UpdateGroupsGroupScoresAndSave.call(group:).success?
    end

    return if @match.group_match?

    if @match.winner.nil?
      render json: { error: 'Stopping undecided Matches isn\'t allowed in playoff stage' },
             status: :unprocessable_entity
      raise ActiveRecord::Rollback
    end

    return if PopulateMatchBelowAndSave.call(match: @match).success?

    render json: { error: 'Moving Team one stage down failed' },
           status: :unprocessable_entity
    raise ActiveRecord::Rollback
  end

  def validate_params
    case match_params['state']
    when 'in_progress'
      render json: { error: 'Match can\'t start in this state' }, status: :unprocessable_entity unless @match.not_started?
    when 'finished'
      render json: { error: 'Match can\'t finish in this state' }, status: :unprocessable_entity unless @match.in_progress?
    else
      render json: { error: 'Invalid target state' }, status: :unprocessable_entity
    end
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
    params.slice(:state).permit!
  end

  def match_index_params
    params.slice(:state, :stage_id, :stage_level, :position, :group_stage_position).permit!
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
      match_scores: teams.map { |team| MatchScore.new(team:) }
    ).tap do |match|
      match.errors.add(:team_ids, 'must contain exactly two teams from this group') if team_ids.size != 2 || teams.size != 2
    end
  end

  def push_sync_if_needed!(tournament)
    TournamentSyncEnqueue.call(tournament)
  end
end
