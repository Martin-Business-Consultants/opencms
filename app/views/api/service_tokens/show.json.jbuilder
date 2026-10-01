# frozen_string_literal: true

json.service_token do
  json.partial! "api/service_tokens/service_token", record: @service_token
end
