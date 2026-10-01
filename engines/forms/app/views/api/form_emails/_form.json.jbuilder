# frozen_string_literal: true

# The form as the email editor needs it: its fields, and which of them hold an
# address a confirmation can go to.
json.merge! record.as_json(only: %i[id slug title])
json.fields record.fields
json.email_fields(record.fields.select { |field| field.is_a?(Hash) && field["type"] == "email" })
