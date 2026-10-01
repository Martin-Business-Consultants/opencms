# frozen_string_literal: true

json.review_requests @review_requests, partial: "api/review_requests/review_request", as: :record
json.states ReviewRequest::STATES
