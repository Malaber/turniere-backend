# frozen_string_literal: true

class BeamerSerializer < ApplicationSerializer
  attributes :name, :display_state, :qr_code_url, :logo_url
end
