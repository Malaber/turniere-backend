# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TournamentSyncSchema do
  describe 'column coverage' do
    described_class::MODEL_COLUMNS.each_key do |model_class|
      it "accounts for every #{model_class.name} column in sync contract" do
        synced_columns = described_class.synced_columns_for(model_class)
        ignored_columns = described_class.ignored_columns_for(model_class)
        accounted_columns = synced_columns + ignored_columns

        expect(accounted_columns.uniq).to match_array(model_class.column_names)
        expect(synced_columns & ignored_columns).to be_empty
      end
    end
  end
end
