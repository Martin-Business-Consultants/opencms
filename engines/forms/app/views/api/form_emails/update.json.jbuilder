# frozen_string_literal: true

json.email do
  json.partial! "api/form_emails/email", record: @email
end
