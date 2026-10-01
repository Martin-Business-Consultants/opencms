# frozen_string_literal: true

json.block_type do
  json.partial! "api/block_types/block_type", record: @block_type
end
