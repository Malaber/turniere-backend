# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    def connect
      MetricsRegistry.action_cable_connected
    end

    def disconnect
      MetricsRegistry.action_cable_disconnected
    end
  end
end
