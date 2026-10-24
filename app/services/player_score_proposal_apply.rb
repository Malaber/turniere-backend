# frozen_string_literal: true

class PlayerScoreProposalApply
  FIELDS = %w[proposal_id revision sequence tournament_id match_id base_score_revision team_ids scores].freeze

  def self.call(tournament, payload)
    new(tournament, payload).call
  end

  def initialize(tournament, payload)
    @tournament = tournament
    @payload = payload
  end

  def call
    validate_shape!
    Tournament.transaction do
      @tournament = TournamentTransactionLogger.lock_tournament!(tournament)
      return :disabled unless tournament.sync_push_enabled?
      return :duplicate if PlayerScoreReceipt.exists?(tournament: tournament, source_match_id: payload['match_id']) ||
                           PlayerScoreReceipt.exists?(tournament: tournament, proposal_id: payload['proposal_id'])

      match = tournament.matches.find { |candidate| candidate.id == payload['match_id'] }
      raise PlayerScoreProposalService::Invalid, 'Match is outside the configured tournament' if match.nil?

      outcome = eligibility(match)
      old_scores = match.match_scores.to_h { |score| [score.team_id.to_s, score.points] }
      if outcome == 'applied'
        match.match_scores.each { |score| score.update!(points: payload['scores'].fetch(score.team_id.to_s)) }
        match.update!(score_revision: match.score_revision + 1)
      end
      PlayerScoreReceipt.create!(tournament: tournament, source_match_id: match.id,
                                 proposal_id: payload['proposal_id'], proposal: payload, outcome: outcome)
      TournamentTransactionLogger.record!(
        tournament: tournament, user: nil, action: "match.player_score_#{outcome}",
        message: "Player score proposal #{payload['proposal_id']} #{outcome} for match #{match.id}",
        metadata: { match_id: match.id, proposal: payload, previous_scores: old_scores,
                    proposed_scores: payload['scores'], outcome: outcome }
      )
      # Queue only canonical live points. No finish/standings/bracket service is called.
      if outcome == 'applied'
        TournamentSyncEnqueue.call(tournament)
        ActiveRecord.after_all_transactions_commit { TournamentLiveBroadcast.call(tournament.id) }
      end
      outcome.to_sym
    end
  end

  private

  attr_reader :tournament, :payload

  def validate_shape!
    valid = payload.is_a?(Hash) && payload.keys.sort == FIELDS.sort &&
            payload['proposal_id'].is_a?(String) && payload['proposal_id'].match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/) &&
            %w[revision sequence tournament_id match_id].all? { |field| payload[field].is_a?(Integer) && payload[field].positive? } &&
            payload['base_score_revision'].is_a?(Integer) && payload['base_score_revision'] >= 0 &&
            payload['team_ids'].is_a?(Array) && payload['team_ids'].size == 2 &&
            payload['team_ids'].all? { |id| id.is_a?(Integer) && id.positive? } && payload['team_ids'].uniq.size == 2
    raise PlayerScoreProposalService::Invalid, 'Invalid proposal envelope' unless valid
    raise PlayerScoreProposalService::Invalid, 'Tournament identity does not match' unless payload['tournament_id'] == tournament.id

    PlayerScoreProposalService.scores!(payload['scores'], payload['team_ids'])
  end

  def eligibility(match)
    return 'rejected_admin_override' if match.player_score_blocked?
    return 'rejected_state' unless match.in_progress?
    return 'rejected_revision' unless match.score_revision == payload['base_score_revision']
    return 'rejected_teams' unless match.teams.map(&:id).sort == payload['team_ids'].sort &&
                                   match.match_scores.size == 2 && match.teams.all? { |team| team.tournament_id == tournament.id }

    'applied'
  end
end
