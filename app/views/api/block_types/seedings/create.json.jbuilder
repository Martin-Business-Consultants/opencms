# frozen_string_literal: true

json.seeded @seeded
json.block_types @block_types, partial: "api/block_types/block_type", as: :record
