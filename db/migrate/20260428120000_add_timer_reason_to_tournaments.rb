# frozen_string_literal: true

class AddTimerReasonToTournaments < ActiveRecord::Migration[7.0]
  def change
    add_column :tournaments, :timer_reason, :string
    add_column :tournaments, :timer_reason_text, :text
  end
end
