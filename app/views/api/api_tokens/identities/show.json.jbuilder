# frozen_string_literal: true

owner = Current.api_user || Current.api_token
permissions = owner&.role&.permissions || []

json.token do
  json.partial! "api/api_tokens/token", record: @token
end
json.capabilities permissions.include?(Permissions::WILDCARD) ? Permissions.all : (permissions & Permissions.all)
if Current.api_user
  json.user do
    json.id Current.api_user.id
    json.name Current.api_user.name
    json.email Current.api_user.email
  end
else
  json.service do
    json.id @token.id
    json.name @token.name
    json.role @token.role&.name
  end
end
