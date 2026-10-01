# frozen_string_literal: true

# An entry as a collection lists it: enough to pick one to open.
json.extract! entry, :id, :slug, :title, :status, :locale, :published_at, :updated_at
json.partial! "api/collection_entries/taxonomy", entry: entry
