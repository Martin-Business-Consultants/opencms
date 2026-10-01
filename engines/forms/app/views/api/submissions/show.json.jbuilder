# frozen_string_literal: true

json.submission do
  json.partial! "api/submissions/submission", record: @submission
end
