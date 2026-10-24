# frozen_string_literal: true

module PlayerScoreSetup
  def setup_player_scores
    @leader = create(:tournament, teams_count: 2, sync_target_url: 'https://remote.example/tournaments/99/sync_state', sync_auth_token: 'secret')
    @stage = Stage.create!(tournament: @leader, level: 0, state: :in_progress)
    @match = Match.create!(stage: @stage, state: :in_progress)
    @leader.teams.each { |team| MatchScore.create!(match: @match, team: team, points: 0, hidden_points: 0) }
    @match.reload
    @follower = create(:tournament, teams_count: 0, read_only_mode: true, sync_auth_token: 'secret')
    replicate
    @remote = @follower.reload.matches.first
    @teams = @remote.teams.sort_by(&:sync_source_id)
    @players = [create(:user), create(:user), create(:user)]
    @teams.first.players << @players[0] << @players[1]
    @teams.last.players << @players[2]
  end

  def replicate
    TournamentSnapshotImporter.import!(tournament: @follower.reload, snapshot: TournamentSnapshotBuilder.build(@leader.reload))
  end

  def remote_scores(a = 7, b = 10)
    { @teams.first.id.to_s => a, @teams.last.id.to_s => b }
  end

  def propose(player = 0, scores = remote_scores)
    PlayerScoreProposalService.submit!(match: @remote, user: @players[player],
                                      team_id: @teams[player == 2 ? 1 : 0].id, scores: scores)
  end

  def agree
    propose
    propose(2)
  end
end
