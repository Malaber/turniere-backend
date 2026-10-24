# frozen_string_literal: true

require 'net/http'
require 'json'

class PlayerScoreProposalPoller
  MAX_BODY_BYTES = 256 * 1024

  def self.poll_all!
    Tournament.where(read_only_mode: false).where.not(sync_target_url: [nil, '']).find_each do |tournament|
      new(tournament).poll!
    rescue StandardError => e
      Rails.logger.warn("Player score proposal poll failed for tournament #{tournament.id}: #{e.class}")
    end
  end

  def initialize(tournament)
    @tournament = tournament
  end

  def poll!
    return unless tournament.sync_push_enabled?

    payload = fetch
    proposals = payload.fetch('proposals')
    raise PlayerScoreProposalService::Invalid, 'Invalid polling batch' unless proposals.is_a?(Array) && proposals.size <= 100

    proposals.each do |proposal|
      sequence = proposal.is_a?(Hash) && proposal['sequence']
      raise PlayerScoreProposalService::Invalid, 'Invalid polling sequence' unless sequence.is_a?(Integer) && sequence.positive?

      Tournament.transaction do
        @tournament = TournamentTransactionLogger.lock_tournament!(tournament)
        next if sequence <= tournament.score_proposal_cursor

        begin
          PlayerScoreProposalApply.call(tournament, proposal)
        rescue PlayerScoreProposalService::Invalid => e
          Rails.logger.warn("Rejected malformed player proposal for tournament #{tournament.id}: #{e.message}")
        end
        tournament.update!(score_proposal_cursor: sequence)
      end
    end
  end

  private

  attr_reader :tournament

  def fetch
    uri = URI.parse(tournament.sync_target_url)
    raise PlayerScoreProposalService::Invalid, 'Sync URL must end in /sync_state' unless uri.path.end_with?('/sync_state')

    uri.path = "#{uri.path.delete_suffix('/sync_state')}/locked_score_proposals"
    uri.query = URI.encode_www_form(after: tournament.score_proposal_cursor)
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{tournament.sync_auth_token}"
    request['Accept'] = 'application/json'
    body = +''
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 5) do |http|
      http.request(request) do |response|
        raise PlayerScoreProposalService::Invalid, 'Proposal endpoint did not succeed' unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          body << chunk
          raise PlayerScoreProposalService::Invalid, 'Proposal response too large' if body.bytesize > MAX_BODY_BYTES
        end
      end
    end
    JSON.parse(body)
  end
end
