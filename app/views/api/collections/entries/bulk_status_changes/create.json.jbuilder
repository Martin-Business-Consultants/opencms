# frozen_string_literal: true

json.updated @entries.size
json.status @status
json.slugs @entries.map(&:slug)
json.not_found @not_found
