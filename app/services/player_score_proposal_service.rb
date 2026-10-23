# frozen_string_literal: true

class PlayerScoreProposalService
  class Forbidden < StandardError; end
  class Conflict < StandardError; end
  class Invalid < StandardError; end
  MAX_POINTS = 1000

  def self.scores!(scores, team_ids)
    valid = scores.is_a?(Hash) && scores.keys.sort == team_ids.map(&:to_s).sort &&
            scores.values.all? { |value| value.is_a?(Integer) && value.between?(0, MAX_POINTS) }
    raise Invalid, 'Provide integer points from 0 to 1000 for exactly the two participating teams' unless valid

    scores
  end

  def self.eligible_team_ids(match, user)
    return [] if user.nil?

    match.teams.select { |team| team.players.exists?(id: user.id) }.map(&:id)
  end

  def self.mapped_teams!(match)
    teams = match.teams.to_a
    ids = teams.map(&:sync_source_id)
    raise Conflict, 'Match has no complete leader mapping' unless ids.size == 2 && ids.all? && ids.uniq.size == 2 && match.sync_source_id

    teams.sort_by(&:sync_source_id)
  end

  def self.submit!(match:, user:, team_id:, scores:)
    Tournament.transaction do
      tournament = TournamentTransactionLogger.lock_tournament!(match.tournament)
      match.reload
      raise Forbidden, 'Player proposals are only available on a configured follower' unless tournament.sync_accepts_push?
      raise Forbidden, 'You must belong to the submitting team' unless eligible_team_ids(match, user).include?(team_id)
      raise Conflict, 'Match is not accepting player scores' unless match.in_progress? && !match.player_score_blocked?
      raise Conflict, 'Decider scores require an organizer' if match.decider?

      teams = mapped_teams!(match)
      ids = teams.map(&:sync_source_id)

      local_scores = scores!(scores, teams.map(&:id))
      canonical_scores = teams.to_h { |team| [team.sync_source_id.to_s, local_scores.fetch(team.id.to_s)] }
      proposal = PlayerScoreProposal.find_or_initialize_by(tournament: tournament, source_match_id: match.sync_source_id)
      raise Conflict, 'Team agreement is locked and cannot be resubmitted' if proposal.locked_at?

      if proposal.new_record? || proposal.base_score_revision != match.score_revision || proposal.team_ids != ids
        proposal.assign_attributes(proposal_id: SecureRandom.uuid, base_score_revision: match.score_revision,
                                   team_ids: ids, team_proposals: {})
      end
      submitting_source_id = teams.find { |team| team.id == team_id }.sync_source_id.to_s
      proposal.team_proposals = proposal.team_proposals.merge(submitting_source_id => { 'scores' => canonical_scores,
                                                                                        'user_id' => user.id })
      proposal.revision += 1
      values = proposal.team_proposals.values.map { |entry| entry.fetch('scores') }
      if values.size == 2 && values.first == values.last
        proposal.agreed_scores = values.first
        proposal.locked_at = Time.current
        proposal.locked_sequence = (PlayerScoreProposal.where(tournament: tournament).maximum(:locked_sequence) || 0) + 1
      end
      proposal.save!
      proposal
    end
  end
end
