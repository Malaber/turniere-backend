# frozen_string_literal: true

class AccountSummarySerializer < ApplicationSerializer
  attributes :name, :username

  def name
    object.username
  end
end
