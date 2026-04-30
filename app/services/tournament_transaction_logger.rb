# frozen_string_literal: true

class TournamentTransactionLogger
  class << self
    def lock_tournament!(tournament)
      raise ArgumentError, 'tournament is required' if tournament.nil?

      unless ActiveRecord::Base.connection.transaction_open?
        raise 'Tournament transaction log writes must happen inside a transaction'
      end

      tournament.lock!
    end

    def record!(tournament:, user:, action:, message:, metadata: {})
      retries = 0

      begin
        Tournament.transaction(requires_new: true) do
          lock_tournament!(tournament)
          TournamentTransactionLogEntry.create!(
            tournament: tournament,
            user: user,
            sequence: next_sequence_for(tournament),
            action: action,
            message: message,
            metadata: metadata.deep_stringify_keys
          )
        end
      rescue ActiveRecord::RecordNotUnique
        retries += 1
        retry if retries < 3

        raise
      end
    end

    def record_tournament_created!(tournament:, user:)
      record!(
        tournament: tournament,
        user: user,
        action: 'tournament.created',
        message: "#{user_label(user)} created tournament #{tournament.name}(#{tournament.id})",
        metadata: {
          tournament_id: tournament.id,
          tournament_name: tournament.name
        }
      )
    end

    def record_timer_changed!(tournament:, user:, old_timer:, new_timer:)
      record!(
        tournament: tournament,
        user: user,
        action: 'tournament.timer_changed',
        message: "#{user_label(user)} changed tournament timer for #{tournament.name}(#{tournament.id})",
        metadata: {
          old_timer: old_timer,
          new_timer: new_timer
        }
      )
    end

    def record_match_state_change!(match:, user:, old_state:, new_state:, details: {})
      match.reload
      stage_type = match.group_match? ? 'groupstage' : 'playoffs'
      group_scores = details.fetch(:group_scores, [])
      advanced_match_ids = details.fetch(:advanced_match_ids, [])
      metadata = match_metadata(match).merge(
        old_state: old_state,
        new_state: new_state,
        stage_type: stage_type,
        winner_team_id: match.winner&.id,
        advanced_match_ids: advanced_match_ids,
        group_scores: group_scores_metadata(group_scores)
      )

      record!(
        tournament: match.tournament,
        user: user,
        action: 'match.state_changed',
        message: match_state_message(
          match: match,
          user: user,
          new_state: new_state,
          details: details.merge(stage_type: stage_type)
        ),
        metadata: metadata
      )
    end

    def record_match_score_update!(match_score:, user:, changes:, group_scores: [])
      return if changes.empty?

      match_score.reload
      match = match_score.match
      metadata = match_metadata(match).merge(
        match_score_id: match_score.id,
        team_id: match_score.team_id,
        changes: changes,
        group_scores: group_scores_metadata(group_scores)
      )

      record!(
        tournament: match.tournament,
        user: user,
        action: 'match_score.updated',
        message: match_score_message(
          match_score: match_score,
          user: user,
          changes: changes,
          group_scores: group_scores
        ),
        metadata: metadata
      )
    end

    def record_decider_match_created!(match:, user:, group_scores: [])
      record!(
        tournament: match.tournament,
        user: user,
        action: 'decider_match.created',
        message: "#{user_label(user)} added decider match #{match.id} (#{match_teams_label(match)})",
        metadata: match_metadata(match).merge(group_scores: group_scores_metadata(group_scores))
      )
    end

    def record_playoffs_start_failed!(stage:, user:, reason:, blocking_ties: [])
      record!(
        tournament: stage.tournament,
        user: user,
        action: 'playoffs.start_failed',
        message: playoffs_start_failed_message(user: user, reason: reason, blocking_ties: blocking_ties),
        metadata: {
          stage_id: stage.id,
          reason: reason,
          blocking_ties: blocking_ties
        }
      )
    end

    def record_playoffs_started!(stage:, user:, advancing_teams:)
      record!(
        tournament: stage.tournament,
        user: user,
        action: 'playoffs.started',
        message: "#{user_label(user)} started playoffs, advancing teams: #{team_list_label(advancing_teams)}",
        metadata: {
          stage_id: stage.id,
          advancing_team_ids: advancing_teams.map(&:id),
          advancing_teams: teams_metadata(advancing_teams)
        }
      )
    end

    def record_group_matches_started!(tournament:, user:, matches:)
      return if matches.empty?

      record!(
        tournament: tournament,
        user: user,
        action: 'group_matches.started',
        message: "#{user_label(user)} started group matches: #{matches.map(&:id).join(', ')}",
        metadata: {
          match_ids: matches.map(&:id),
          matches: matches.map { |match| match_metadata(match) }
        }
      )
    end

    private

    def next_sequence_for(tournament)
      TournamentTransactionLogEntry.where(tournament_id: tournament.id).maximum(:sequence).to_i + 1
    end

    def user_label(user)
      user&.username.presence || user&.email.presence || 'system'
    end

    def state_label(state)
      {
        'in_progress' => 'running',
        'not_started' => 'not started',
        'not_ready' => 'not ready',
        'single_team' => 'single team',
        'undecided' => 'undecided',
        'finished' => 'finished'
      }.fetch(state.to_s, state.to_s)
    end

    def match_state_message(match:, user:, new_state:, details:)
      group_scores = details.fetch(:group_scores, [])
      advanced_match_ids = details.fetch(:advanced_match_ids, [])
      stage_type = details.fetch(:stage_type)

      if new_state.to_s == 'finished'
        return finished_group_match_message(match, user, group_scores) if match.group_match?

        return finished_playoff_match_message(match, user, stage_type, advanced_match_ids)
      end

      message = "#{user_label(user)} changed match #{match.id} " \
                "(#{match_teams_label(match)}) to #{state_label(new_state)}"
      message += ' - scores reset' if new_state.to_s == 'not_started'
      message
    end

    def finished_group_match_message(match, user, group_scores)
      "#{user_label(user)} changed match #{match.id} to finished (#{finish_result_label(match)}) - " \
        "groupstage - group scores recalculated (#{group_scores_label(group_scores)})"
    end

    def finished_playoff_match_message(match, user, stage_type, advanced_match_ids)
      message = "#{user_label(user)} changed match #{match.id} to finished " \
                "(#{finish_result_label(match)}) - #{stage_type}"
      return message if advanced_match_ids.empty? || match.winner.nil?

      "#{message} - #{team_label(match.winner)} advances to match #{advanced_match_ids.join(', ')}"
    end

    def match_score_message(match_score:, user:, changes:, group_scores:)
      match = match_score.match
      change_label = changes.map do |field, values|
        "#{field} from #{values.fetch(:from)} to #{values.fetch(:to)}"
      end.join(', ')
      message = "#{user_label(user)} changed matchscore #{match_score.id} from match #{match.id}: #{change_label} " \
                "(#{score_detail_label(match_score, changes)})"
      return message unless match.group_match?

      "#{message} - group scores recalculated (#{group_scores_label(group_scores)})"
    end

    def playoffs_start_failed_message(user:, reason:, blocking_ties:)
      case reason.to_s
      when 'decider_missing'
        "#{user_label(user)} attempted playoff start, failed because decider missing " \
          "(#{blocking_ties_label(blocking_ties)})"
      when 'unfinished_matches'
        "#{user_label(user)} attempted playoff start, failed because group stage has unfinished matches"
      else
        "#{user_label(user)} attempted playoff start, failed because #{reason}"
      end
    end

    def finish_result_label(match)
      winner = match.winner
      return "#{team_label(winner)} wins" unless winner.nil?

      teams = match.teams
      return "draw between #{team_label(teams.first)} and #{team_label(teams.second)}" if teams.size == 2

      'no winner'
    end

    def score_detail_label(match_score, changes)
      team = match_score.team
      opponent = match_score.match.teams.find { |candidate| candidate.id != team.id }
      field = score_detail_field(changes)
      points = score_detail_points(match_score, changes, field)
      "#{points} #{field.to_s.tr('_', ' ')} for #{team_label(team)} in match vs #{team_label(opponent)}"
    end

    def score_detail_field(changes)
      return :hidden_points if changes.key?(:hidden_points) || changes.key?('hidden_points')

      :points
    end

    def score_detail_points(match_score, changes, field)
      changes.dig(field.to_s, :to) ||
        changes.dig(field, :to) ||
        match_score.public_send(field)
    end

    def match_teams_label(match)
      teams = match.teams
      return "between #{team_label(teams.first)} and #{team_label(teams.second)}" if teams.size == 2
      return "with #{team_label(teams.first)}" if teams.size == 1

      'without assigned teams'
    end

    def team_label(team)
      return 'unknown team' if team.nil?

      "#{team.name}(#{team.id})"
    end

    def team_list_label(teams)
      teams.map { |team| team_label(team) }.join(', ')
    end

    def blocking_ties_label(blocking_ties)
      blocking_ties.map do |tie|
        names = tie.fetch(:team_names, [])
        ids = tie.fetch(:team_ids, [])
        names.zip(ids).map { |name, id| "#{name}(#{id})" }.join(' vs ')
      end.join(', ')
    end

    def group_scores_label(group_scores)
      group_scores_metadata(group_scores).map do |score|
        "#{score.fetch(:team_name)}(#{score.fetch(:team_id)}) groupscore " \
          "#{score.fetch(:group_points)}-#{score.fetch(:scored_points)}-#{score.fetch(:received_points)} " \
          "pos #{score.fetch(:position)}"
      end.join(', ')
    end

    def group_scores_metadata(group_scores)
      Array(group_scores).map do |score|
        score.reload if score.persisted?
        {
          id: score.id,
          team_id: score.team_id,
          team_name: score.team.name,
          group_points: score.group_points,
          scored_points: score.scored_points,
          received_points: score.received_points,
          position: score.position
        }
      end
    end

    def match_metadata(match)
      {
        match_id: match.id,
        decider: match.decider?,
        group_id: match.group_id,
        stage_id: match.stage_id,
        team_ids: match.teams.map(&:id),
        teams: teams_metadata(match.teams)
      }
    end

    def teams_metadata(teams)
      teams.map do |team|
        {
          id: team.id,
          name: team.name
        }
      end
    end
  end
end
