# frozen_string_literal: true

json.entries @entries do |(kind, record)|
  json.partial! "api/trash/entry", kind: kind, record: record
end
json.counts Trash.counts
json.kinds Trash.kinds.keys
