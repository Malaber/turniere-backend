# frozen_string_literal: true

class BackfillDefaultBeamersByName < ActiveRecord::Migration[7.0]
  DEFAULT_BEAMER_NAME = 'default'

  class MigrationTournament < ApplicationRecord
    self.table_name = 'tournaments'
  end

  class MigrationBeamer < ApplicationRecord
    self.table_name = 'beamers'
  end

  def up
    MigrationTournament.find_each do |tournament|
      beamers = MigrationBeamer.where(tournament_id: tournament.id)
      next if beamers.exists?(name: DEFAULT_BEAMER_NAME)

      legacy_default = beamers.find_by(is_default: true)

      if legacy_default
        legacy_default.update_columns(name: DEFAULT_BEAMER_NAME)
      else
        MigrationBeamer.create!(
          tournament_id: tournament.id,
          name: DEFAULT_BEAMER_NAME,
          display_state: 'matches_all'
        )
      end
    end
  end

  def down
    MigrationBeamer.where(name: DEFAULT_BEAMER_NAME).where.not(tournament_id: nil).find_each do |beamer|
      next unless MigrationBeamer.where(tournament_id: beamer.tournament_id).count == 1

      beamer.delete
    end
  end
end
