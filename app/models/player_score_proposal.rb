# frozen_string_literal: true

# Follower-owned workflow state. Never included in canonical snapshots.
class PlayerScoreProposal < ApplicationRecord
  belongs_to :tournament

  def locked_payload
    {
      proposal_id: proposal_id, revision: revision, sequence: locked_sequence,
      tournament_id: tournament.sync_source_tournament_id, match_id: source_match_id,
      base_score_revision: base_score_revision, team_ids: team_ids, scores: agreed_scores
    }
  end
end
