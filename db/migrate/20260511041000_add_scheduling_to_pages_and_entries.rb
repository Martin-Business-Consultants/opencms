# frozen_string_literal: true

# Schedule a future publish or unpublish. The recurring
# `ProcessScheduledPublishingJob` flips status when the time arrives;
# until then these are just timestamps with no behavioral effect.
class AddSchedulingToPagesAndEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :pages, :publish_at,   :datetime
    add_column :pages, :unpublish_at, :datetime
    add_index  :pages, :publish_at
    add_index  :pages, :unpublish_at

    add_column :collection_entries, :publish_at,   :datetime
    add_column :collection_entries, :unpublish_at, :datetime
    add_index  :collection_entries, :publish_at
    add_index  :collection_entries, :unpublish_at
  end
end
