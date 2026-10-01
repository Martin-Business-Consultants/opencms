# frozen_string_literal: true

json.form do
  json.partial! "api/form_emails/form", record: @form
end
json.email do
  json.partial! "api/form_emails/email", record: @email
end
json.available_tokens @available_tokens
