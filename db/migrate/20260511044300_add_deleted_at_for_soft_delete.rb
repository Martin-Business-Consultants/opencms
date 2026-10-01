# frozen_string_literal: true

# Soft-delete columns. The matching `SoftDeletable` concern adds a
# default_scope so existing reads ignore discarded rows. Index lets the
# trash UI and the daily purge job scan efficiently.
class AddDeletedAtForSoftDelete < ActiveRecord::Migration[8.0]
  TARGETS = %i[pages collection_entries assets forms globals].freeze

  def change
    TARGETS.each do |table|
      add_column table, :deleted_at, :datetime
      add_index  table, :deleted_at
    end
  end
end
