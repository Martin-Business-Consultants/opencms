# frozen_string_literal: true

if @match
  json.match       true
  json.source      @match[:redirect].source_path
  json.destination @match[:destination]
  json.status      @match[:status]
else
  json.match false
end
