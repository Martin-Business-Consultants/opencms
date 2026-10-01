# frozen_string_literal: true

json.extract! entry, :id, :slug, :title, :status, :locale, :published_at, :created_at, :updated_at
json.partial! "api/collection_entries/taxonomy", entry: entry
