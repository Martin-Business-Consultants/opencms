# frozen_string_literal: true

json.deleted @collections.size
json.slugs @collections.map(&:slug)
json.not_found @not_found
