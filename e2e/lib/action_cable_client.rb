# frozen_string_literal: true

require 'json'
require 'socket'
require 'openssl'
require 'uri'
require 'websocket/driver'

module TurniereE2E
  class ActionCableClient
    ACTION_CABLE_PROTOCOLS = %w[actioncable-v1-json actioncable-unsupported].freeze

    def initialize(base_url:)
      @base_url = base_url.sub(%r{/\z}, '')
      @messages = Queue.new
      @closed = false
    end

    def subscribe_team_action_lists!(tournament_id:)
      identifier = {
        channel: 'TournamentTeamActionListsChannel',
        tournament_id: tournament_id
      }.to_json

      subscribe!(identifier:) do |message|
        team_action_lists_payload_message?(message)
      end
    end

    def subscribe_timer!(tournament_id:)
      identifier = {
        channel: 'TournamentTimersChannel',
        tournament_id: tournament_id
      }.to_json

      subscribe!(identifier:) do |message|
        timer_payload_message?(message)
      end
    end

    def subscribe_beamer!(tournament_id:, beamer_name:)
      identifier = {
        channel: 'TournamentBeamersChannel',
        tournament_id: tournament_id,
        beamer_name: beamer_name
      }.to_json

      subscribe!(identifier:) do |message|
        beamer_payload_message?(message)
      end
    end

    def subscribe_tournament!(tournament_id:)
      identifier = {
        channel: 'TournamentChannel',
        tournament_id: tournament_id
      }.to_json

      subscribe!(identifier:) do |message|
        tournament_payload_message?(message)
      end
    end

    def subscribe_matches!(tournament_id:, state: nil)
      identifier = {
        channel: 'TournamentMatchesChannel',
        tournament_id: tournament_id,
        state: state
      }.compact.to_json

      subscribe!(identifier:) do |message|
        matches_payload_message?(message)
      end
    end

    def wait_for_payload!(timeout: 20)
      wait_for!(timeout: timeout) do |message|
        team_action_lists_payload_message?(message)
      end.fetch('message')
    end

    def wait_for_timer_payload!(timeout: 20)
      wait_for!(timeout: timeout) do |message|
        timer_payload_message?(message)
      end.fetch('message')
    end

    def wait_for_beamer_payload!(timeout: 20)
      wait_for!(timeout: timeout) do |message|
        beamer_payload_message?(message)
      end.fetch('message')
    end

    def wait_for_tournament_payload!(timeout: 20)
      wait_for!(timeout: timeout) do |message|
        tournament_payload_message?(message)
      end.fetch('message')
    end

    def wait_for_matches_payload!(timeout: 20)
      wait_for!(timeout: timeout) do |message|
        matches_payload_message?(message)
      end.fetch('message')
    end

    def close
      return if @closed

      @closed = true
      @driver&.close
      @socket&.close
    rescue IOError, SystemCallError
      nil
    end

    def url
      websocket_url
    end

    def write(data)
      socket.write(data)
    end

    private

    attr_reader :base_url, :socket, :driver

    def subscribe!(identifier:)
      connect!

      driver.text(
        JSON.dump(
          command: 'subscribe',
          identifier: identifier
        )
      )

      handshake_message = wait_for! do |message|
        message['type'] == 'confirm_subscription' ||
          (message['identifier'] == identifier && yield(message))
      end

      @messages << handshake_message if yield(handshake_message)
    end

    def connect!
      return unless @driver.nil?

      @socket = build_socket
      @driver = WebSocket::Driver.client(self, protocols: ACTION_CABLE_PROTOCOLS)
      @driver.set_header('Origin', http_origin)
      @driver.on(:message) { |event| @messages << JSON.parse(event.data) }
      @driver.start
      pump_until_open!
    end

    def build_socket
      uri = URI.parse(websocket_url)
      tcp_socket = TCPSocket.new(uri.host, uri.port)
      return tcp_socket unless uri.scheme == 'wss'

      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context)
      ssl_socket.hostname = uri.host if ssl_socket.respond_to?(:hostname=)
      ssl_socket.connect
      ssl_socket
    end

    def websocket_url
      uri = URI.parse(base_url)
      uri.scheme = uri.scheme == 'https' ? 'wss' : 'ws'
      uri.path = '/cable'
      uri.query = nil
      uri.to_s
    end

    def http_origin
      uri = URI.parse(base_url)
      "#{uri.scheme}://#{uri.host}:#{uri.port}"
    end

    def pump_until_open!(timeout: 10)
      deadline = Time.now + timeout
      while Time.now < deadline
        read_from_socket(timeout: 0.5)
        return if driver.ready_state == 1
      end

      raise "websocket did not open within #{timeout}s"
    end

    def wait_for!(timeout: 20)
      deadline = Time.now + timeout
      loop do
        until @messages.empty?
          message = @messages.pop(true)
          return message if yield(message)
        end

        raise "websocket message not received within #{timeout}s" if Time.now >= deadline

        read_from_socket(timeout: 0.5)
      rescue ThreadError
        nil
      end
    end

    def read_from_socket(timeout:)
      readable, = IO.select([socket], nil, nil, timeout)
      return if readable.nil?

      chunk = socket.readpartial(4096)
      driver.parse(chunk)
    rescue EOFError
      nil
    end

    def team_action_lists_payload_message?(message)
      payload = message['message']
      payload.is_a?(Hash) && payload['type'] == 'team_action_lists.updated'
    end

    def timer_payload_message?(message)
      payload = message['message']
      payload.is_a?(Hash) && payload['type'] == 'timer.updated'
    end

    def beamer_payload_message?(message)
      payload = message['message']
      payload.is_a?(Hash) && payload['type'].to_s.start_with?('beamer.')
    end

    def tournament_payload_message?(message)
      payload = message['message']
      payload.is_a?(Hash) && payload['type'] == 'tournament.updated'
    end

    def matches_payload_message?(message)
      payload = message['message']
      payload.is_a?(Hash) && payload['type'] == 'tournament_matches.updated'
    end
  end
end
