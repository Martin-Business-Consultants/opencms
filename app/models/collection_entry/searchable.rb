# frozen_string_literal: true

# Entries are indexed in the `collection_entries_fts` FTS5 table (slug, the
# collection's slug, title, and the text of their blocks, body and fields),
# kept in step on every save.
module CollectionEntry::Searchable
  extend ActiveSupport::Concern

  included do
    after_save :sync_fts
    after_destroy :remove_fts
  end

  def search_text
    parts = []
    if blocks.is_a?(Array)
      parts.concat(blocks.filter_map { |hash|
        next unless hash.is_a?(Hash)

        block_type = BlockType.find_by(slug: hash["type"])
        next unless block_type

        block_type.searchable_text(hash["data"] || {})
      })
    end
    parts << body_markdown.to_s
    parts << BlockType.searchable_text_in(collection&.fields || [], frontmatter || {})
    parts.reject(&:blank?).join("\n\n")
  end

  private

  def sync_fts
    connection = self.class.connection
    connection.execute(self.class.send(:sanitize_sql_array, ["DELETE FROM collection_entries_fts WHERE rowid = ?", id]))
    connection.execute(self.class.send(:sanitize_sql_array, [
      "INSERT INTO collection_entries_fts (rowid, slug, collection_slug, title, body) VALUES (?, ?, ?, ?, ?)",
      id, slug, collection.slug, title, search_text
    ]))
  end

  def remove_fts
    connection = self.class.connection
    connection.execute(self.class.send(:sanitize_sql_array, ["DELETE FROM collection_entries_fts WHERE rowid = ?", id]))
  end
end
