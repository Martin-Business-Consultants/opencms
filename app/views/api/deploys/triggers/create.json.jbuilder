# frozen_string_literal: true

json.ok true
json.enqueued true
json.deploy do
  json.partial! "api/deploys/deploy"
end
