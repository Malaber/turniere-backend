# frozen_string_literal: true

class TournamentTransactionLogEntriesController < ApplicationController
  before_action :set_tournament
  before_action :authenticate_user!
  before_action -> { require_owner! @tournament.owner }

  def index
    entries = @tournament.transaction_log_entries.includes(:user).order(:sequence)
    render json: entries, each_serializer: TournamentTransactionLogEntrySerializer
  end

  private

  def set_tournament
    @tournament = Tournament.find(params[:id])
  end
end
