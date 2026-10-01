# frozen_string_literal: true

# One collection; its latest 50 entries when the caller asked for the
# collection itself (show), not when it just saved one.
json.collection do
  json.partial! "api/collections/collection", record: @collection
  json.entries @entries, partial: "api/collections/entry", as: :entry if @entries
end
