# frozen_string_literal: true

Rails.application.config.after_initialize do
  TournamentSyncWorker.start unless Rails.env.test?
end
