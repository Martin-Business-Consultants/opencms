# frozen_string_literal: true

# A whole page. `blocks` is what the caller passes: as stored, or with their
# dynamic data resolved (Page#expanded_blocks) on show.
json.extract! page, :id, :slug, :path, :parent_id, :depth, :title, :status, :locale
json.blocks blocks
json.extract! page, :frontmatter, :seo, :published_at, :created_at, :updated_at
json.partial! "api/pages/taxonomy", page: page
