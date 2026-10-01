# frozen_string_literal: true

json.extract! record, :id, :key, :created_at, :updated_at
json.data record.redacted_data
