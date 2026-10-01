# frozen_string_literal: true

json.deleted @block_types.size
json.slugs @block_types.map(&:slug)
json.not_found @not_found
