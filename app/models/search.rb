# frozen_string_literal: true

# Full-text search over pages and collection entries (SQLite FTS5), 25 of
# each, best match first, with a highlighted snippet.
class Search
  def initialize(query)
    @query = query
  end

  def pages = search_pages(fts_query)

  def entries = search_entries(fts_query)

  private

  # FTS5 has its own query syntax (AND/OR/NEAR/quoted phrases); user input is
  # one phrase, so stray punctuation can't break the query or smuggle in
  # operators.
  def fts_query
    %("#{@query.gsub(/["']/, " ").squeeze(" ").strip}")
  end

  def search_pages(fts_query)
    sql = <<~SQL
      SELECT p.id, p.slug, p.title, p.status, p.locale, p.updated_at,
             snippet(pages_fts, 2, '<mark>', '</mark>', '…', 12) AS snippet
      FROM pages_fts
      JOIN pages p ON p.id = pages_fts.rowid
      WHERE pages_fts MATCH ?
      ORDER BY rank
      LIMIT 25
    SQL

    rows = Page.connection.exec_query(
      Page.send(:sanitize_sql_array, [sql, fts_query]),
      "Page FTS"
    )
    rows.to_a
  end

  def search_entries(fts_query)
    sql = <<~SQL
      SELECT e.id, e.slug, c.slug AS collection_slug, e.title, e.status, e.locale, e.updated_at,
             snippet(collection_entries_fts, 3, '<mark>', '</mark>', '…', 12) AS snippet
      FROM collection_entries_fts
      JOIN collection_entries e ON e.id = collection_entries_fts.rowid
      JOIN collections c ON c.id = e.collection_id
      WHERE collection_entries_fts MATCH ?
      ORDER BY rank
      LIMIT 25
    SQL

    rows = CollectionEntry.connection.exec_query(
      CollectionEntry.send(:sanitize_sql_array, [sql, fts_query]),
      "Entry FTS"
    )
    rows.to_a
  end
end
