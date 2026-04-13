# frozen_string_literal: true

class BeamerSerializer < ApplicationSerializer
  attributes :name, :display_state, :is_default, :qr_code_url, :logo_url
end
