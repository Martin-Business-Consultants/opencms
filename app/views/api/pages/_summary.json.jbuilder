# frozen_string_literal: true

# A page in a list: `path`, `parent_id` and `depth` so a consumer can rebuild
# the tree (nav, sitemaps, breadcrumbs) without fetching every page.
json.extract! page, :id, :slug, :path, :parent_id, :depth, :title, :status, :locale, :published_at, :created_at, :updated_at
json.partial! "api/pages/taxonomy", page: page
