# frozen_string_literal: true

class SimpleTournamentSerializer < ApplicationSerializer
  attributes :name, :code, :public, :location, :organizer_name, :contact_email, :website_url

  attribute :starts_at do
    object.starts_at&.iso8601
  end

  attribute :ends_at do
    object.ends_at&.iso8601
  end
end
