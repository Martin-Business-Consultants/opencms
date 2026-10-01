# frozen_string_literal: true

json.deleted @entries.size
json.slugs @entries.map(&:slug)
json.not_found @not_found
