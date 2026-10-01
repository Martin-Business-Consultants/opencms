# frozen_string_literal: true

json.updated @pages.size
json.status @status
json.paths @pages.map(&:path)
json.not_found @not_found
