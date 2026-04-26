# frozen_string_literal: true

class BackfillDefaultBeamerConfig < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL.squish
      UPDATE beamers
      SET config = '{"match_filter":"state:in_progress"}'
      WHERE name = 'default'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE beamers
      SET config = '{}'
      WHERE name = 'default'
    SQL
  end
end
