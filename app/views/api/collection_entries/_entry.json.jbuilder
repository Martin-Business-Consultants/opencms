# frozen_string_literal: true

# A whole entry.
json.extract! entry, :id, :slug, :title, :status, :locale, :frontmatter, :seo, :body_markdown, :blocks,
  :published_at, :created_at, :updated_at
json.collection_slug entry.collection.slug
json.partial! "api/collection_entries/taxonomy", entry: entry
