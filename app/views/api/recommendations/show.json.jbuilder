# frozen_string_literal: true

json.recommendation do
  json.partial! "api/recommendations/recommendation", record: @recommendation
end
