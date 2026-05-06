# frozen_string_literal: true

class TournamentTransactionLogEntrySerializer < ApplicationSerializer
  attributes :id, :sequence, :action, :message, :metadata

  attribute :created_at do
    object.created_at&.iso8601
  end

  attribute :user do
    next nil if object.user.nil?

    {
      id: object.user.id,
      username: object.user.username
    }
  end
end
