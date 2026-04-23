# frozen_string_literal: true

class TeamActionItemSerializer < ApplicationSerializer
  attributes :completed, :completed_at, :team

  attribute :completed_at do
    object.completed_at&.iso8601
  end

  attribute :team do
    {
      id: object.team.id,
      name: object.team.name
    }
  end
end
