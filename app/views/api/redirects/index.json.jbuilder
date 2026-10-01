# frozen_string_literal: true

# The edge's shape: only what applying a rule needs.
json.redirects @redirects do |redirect|
  json.source      redirect.source_path
  json.destination redirect.destination_url
  json.status      redirect.status_code
  json.wildcard    redirect.wildcard
end
