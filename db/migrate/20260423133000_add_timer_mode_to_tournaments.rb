class AddTimerModeToTournaments < ActiveRecord::Migration[7.0]
  def change
    add_column :tournaments, :timer_mode, :string
  end
end
