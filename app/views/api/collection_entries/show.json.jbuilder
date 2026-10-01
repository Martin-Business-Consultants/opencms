# frozen_string_literal: true

json.entry do
  json.partial! "api/collection_entries/entry", entry: @entry
end
json.assets @assets if instance_variable_defined?(:@assets)
