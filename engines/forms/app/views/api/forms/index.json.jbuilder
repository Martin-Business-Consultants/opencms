# frozen_string_literal: true

json.forms @forms do |form|
  json.partial! "api/forms/form", record: form
end
