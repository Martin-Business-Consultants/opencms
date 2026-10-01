# frozen_string_literal: true

# Per-collection opt-in: when `enable_blocks` is true, a collection's entries
# gain a Page-style `blocks` array alongside their existing frontmatter +
# body_markdown. Lets content-heavy collections (e.g. cities) compose entries
# from the same block library pages use, without forcing every collection to
# carry a blocks editor.
#
# Idempotent on purpose: an earlier iteration of this feature shipped as
# migration 20260618120000 (since removed) which already added the `blocks`
# columns and a `supports_blocks` flag. On a database that ran it, the `blocks`
# columns already exist; here we only add what's missing, carry any
# `supports_blocks` value over to `enable_blocks`, and drop the orphan column.
# On a fresh database, all three columns are created and there is nothing to
# carry over.
class AddBlocksToCollectionEntries < ActiveRecord::Migration[8.0]
  def up
    add_column :collection_entries, :blocks, :json, null: false, default: [], if_not_exists: true
    add_column :collection_entry_versions, :blocks, :json, null: false, default: [], if_not_exists: true
    add_column :collections, :enable_blocks, :boolean, null: false, default: false, if_not_exists: true

    if column_exists?(:collections, :supports_blocks)
      execute("UPDATE collections SET enable_blocks = supports_blocks")
      remove_column :collections, :supports_blocks
    end
  end

  def down
    remove_column :collections, :enable_blocks, if_exists: true
    remove_column :collection_entry_versions, :blocks, if_exists: true
    remove_column :collection_entries, :blocks, if_exists: true
  end
end
