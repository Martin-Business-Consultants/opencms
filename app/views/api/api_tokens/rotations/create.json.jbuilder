# frozen_string_literal: true

json.token do
  json.partial! "api/api_tokens/token", record: @token
end
json.plaintext @plaintext
