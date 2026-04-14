# frozen_string_literal: true

class TournamentSnapshotImporter
  ROOT_ATTRIBUTES = %i[
    name
    code
    description
    public
    playoff_teams_amount
    instant_finalists_amount
    intermediate_round_participants_amount
  ].freeze

  def self.import!(tournament:, snapshot:)
    new(tournament: tournament, snapshot: snapshot).import!
  end

  def initialize(tournament:, snapshot:)
    @tournament = tournament
    @snapshot = snapshot.deep_symbolize_keys
  end

  def import!
    Tournament.transaction do
      tournament.lock!
      return tournament if stale_snapshot?

      existing_teams = tournament.teams.to_a
      existing_stages = tournament.stages.to_a
      existing_groups = existing_stages.flat_map(&:groups)
      existing_matches = tournament.matches
      existing_match_scores = existing_matches.flat_map(&:match_scores)
      existing_group_scores = existing_groups.flat_map(&:group_scores)

      update_tournament!
      teams_by_source_id = sync_teams!
      stages_by_source_id = sync_stages!
      groups_by_source_id = sync_groups!(stages_by_source_id)
      matches_by_source_id = sync_matches!(stages_by_source_id, groups_by_source_id)
      sync_match_scores!(matches_by_source_id, teams_by_source_id)
      sync_group_scores!(groups_by_source_id, teams_by_source_id)

      destroy_stale_records(existing_group_scores, snapshot.fetch(:group_scores, []))
      destroy_stale_records(existing_match_scores, snapshot.fetch(:match_scores, []))
      destroy_stale_records(existing_matches, snapshot.fetch(:matches, []))
      destroy_stale_records(existing_groups, snapshot.fetch(:groups, []))
      destroy_stale_records(existing_stages, snapshot.fetch(:stages, []))
      destroy_stale_records(existing_teams, snapshot.fetch(:teams, []))
    end

    tournament
  end

  private

  attr_reader :tournament, :snapshot

  def update_tournament!
    root_attrs = snapshot.slice(*ROOT_ATTRIBUTES)
    root_attrs[:code] = tournament.code if code_taken_by_another_tournament?(root_attrs[:code])
    root_attrs[:timer_end] = parse_time(snapshot[:timer_end])
    root_attrs[:sync_source_tournament_id] = snapshot[:id]
    root_attrs[:sync_last_imported_snapshot_at] = snapshot_generated_at
    tournament.update!(root_attrs)
  end

  def sync_teams!
    sync_records(
      model_class: Team,
      existing_records: tournament.teams.to_a,
      payload: snapshot.fetch(:teams, [])
    ) do |team, attrs|
      team.tournament = tournament
      team.name = attrs.fetch(:name)
    end
  end

  def sync_stages!
    sync_records(
      model_class: Stage,
      existing_records: tournament.stages.to_a,
      payload: snapshot.fetch(:stages, [])
    ) do |stage, attrs|
      stage.tournament = tournament
      stage.level = attrs.fetch(:level)
      stage.state = attrs.fetch(:state)
    end
  end

  def sync_groups!(stages_by_source_id)
    sync_records(
      model_class: Group,
      existing_records: tournament.stages.flat_map(&:groups),
      payload: snapshot.fetch(:groups, [])
    ) do |group, attrs|
      group.stage = stages_by_source_id.fetch(attrs.fetch(:stage_id))
      group.number = attrs.fetch(:number)
    end
  end

  def sync_matches!(stages_by_source_id, groups_by_source_id)
    sync_records(
      model_class: Match,
      existing_records: tournament.matches,
      payload: snapshot.fetch(:matches, [])
    ) do |match, attrs|
      match.stage = attrs[:stage_id] ? stages_by_source_id.fetch(attrs[:stage_id]) : nil
      match.group = attrs[:group_id] ? groups_by_source_id.fetch(attrs[:group_id]) : nil
      match.state = attrs.fetch(:state)
      match.position = attrs[:position]
      match.decider = attrs[:decider]
    end
  end

  def sync_match_scores!(matches_by_source_id, teams_by_source_id)
    sync_records(
      model_class: MatchScore,
      existing_records: tournament.matches.flat_map(&:match_scores),
      payload: snapshot.fetch(:match_scores, [])
    ) do |match_score, attrs|
      match_score.match = matches_by_source_id.fetch(attrs.fetch(:match_id))
      match_score.team = teams_by_source_id.fetch(attrs.fetch(:team_id))
      match_score.points = attrs.fetch(:points)
      match_score.hidden_points = attrs.fetch(:hidden_points, 0)
    end
  end

  def sync_group_scores!(groups_by_source_id, teams_by_source_id)
    sync_records(
      model_class: GroupScore,
      existing_records: tournament.stages.flat_map(&:groups).flat_map(&:group_scores),
      payload: snapshot.fetch(:group_scores, [])
    ) do |group_score, attrs|
      group_score.group = groups_by_source_id.fetch(attrs.fetch(:group_id))
      group_score.team = teams_by_source_id.fetch(attrs.fetch(:team_id))
      group_score.group_points = attrs.fetch(:group_points)
      group_score.scored_points = attrs.fetch(:scored_points)
      group_score.received_points = attrs.fetch(:received_points)
      group_score.position = attrs.fetch(:position, 0)
    end
  end

  def sync_records(model_class:, existing_records:, payload:)
    existing_by_source_id = existing_records.index_by(&:sync_source_id)

    payload.each_with_object({}) do |attrs, records_by_source_id|
      source_id = attrs.fetch(:id)
      record = existing_by_source_id[source_id] || model_class.new
      record.sync_source_id = source_id
      yield(record, attrs)
      record.save!
      records_by_source_id[source_id] = record
    end
  end

  def destroy_stale_records(existing_records, payload)
    source_ids = payload.map { |attrs| attrs.fetch(:id) }
    stale_records = existing_records.reject { |record| source_ids.include?(record.sync_source_id) }
    stale_records.each(&:destroy!)
  end
  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value)
  end

  def snapshot_generated_at
    parse_time(snapshot[:sync_generated_at])
  end

  def stale_snapshot?
    return false if snapshot_generated_at.nil?
    return false if tournament.sync_last_imported_snapshot_at.nil?

    snapshot_generated_at <= tournament.sync_last_imported_snapshot_at
  end

  def code_taken_by_another_tournament?(code)
    return false if code.blank?

    Tournament.where(code: code).where.not(id: tournament.id).exists?
  end
end
