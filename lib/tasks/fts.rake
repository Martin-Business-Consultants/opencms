# frozen_string_literal: true

# Rebuilds the FTS5 indexes (pages_fts, collection_entries_fts) from scratch.
# Use when the after_save :sync_fts callback was
# bypassed — bulk imports, raw SQL updates, fixtures, etc.
#
#   bin/rails fts:rebuild
namespace :fts do
  desc "Rebuild pages_fts and collection_entries_fts"
  task rebuild: :environment do
    page_conn = Page.connection
    page_conn.execute("DELETE FROM pages_fts")
    Page.find_each { |p| p.send(:sync_fts) }
    puts "Rebuilt pages_fts (#{Page.count} rows)"

    entry_conn = CollectionEntry.connection
    entry_conn.execute("DELETE FROM collection_entries_fts")
    CollectionEntry.find_each { |e| e.send(:sync_fts) }
    puts "Rebuilt collection_entries_fts (#{CollectionEntry.count} rows)"
  end
end
