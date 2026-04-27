# frozen_string_literal: true

class BeamerSerializer < ApplicationSerializer
  attributes :id, :name, :display_state, :config

  delegate :config, to: :object
end
