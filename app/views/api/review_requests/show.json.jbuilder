# frozen_string_literal: true

json.review_request do
  json.partial! "api/review_requests/review_request", record: @review_request
end
