# frozen_string_literal: true

json.deleted @pages.size
json.paths @pages.map(&:path)
json.not_found @not_found
