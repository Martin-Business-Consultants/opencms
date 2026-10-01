# frozen_string_literal: true

json.service_tokens @service_tokens, partial: "api/service_tokens/service_token", as: :record
json.roles @roles do |role|
  json.id role.id
  json.name role.name
  json.description role.description
end
