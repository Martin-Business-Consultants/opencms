# frozen_string_literal: true

json.guides @guides do |guide|
  json.slug guide.slug
  json.title guide.title
  json.summary guide.summary
end
json.go_live "/api/go_live"
