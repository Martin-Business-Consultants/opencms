# frozen_string_literal: true

# The token and its plaintext: only issuing, revealing and rotating say it.
json.service_token do
  json.partial! "api/service_tokens/service_token", record: @service_token
end
json.token @plaintext
