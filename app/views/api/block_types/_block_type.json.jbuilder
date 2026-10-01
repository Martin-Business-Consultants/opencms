# frozen_string_literal: true

json.extract! record, :id, :slug, :label, :description, :category, :icon, :version, :built_in, :deprecated,
  :fields, :defaults, :created_at, :updated_at
json.json_schema record.json_schema
