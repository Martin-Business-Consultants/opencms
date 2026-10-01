# frozen_string_literal: true

json.deleted @globals.size
json.slugs @globals.map(&:slug)
json.not_found @not_found
