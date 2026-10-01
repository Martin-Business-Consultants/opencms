# frozen_string_literal: true

json.extract! record, :id, :name, :url, :active, :events, :event_filters, :headers, :failure_count,
  :last_status, :last_delivery_at, :created_at, :updated_at
json.secret record.secret if local_assigns[:with_secret]
