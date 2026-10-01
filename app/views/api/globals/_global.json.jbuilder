# frozen_string_literal: true

# `record`, not `global`: named for what it is, as the other API partials are.
json.extract! record, :id, :slug, :name, :description, :icon, :version
json.data record.redacted_data
json.extract! record, :created_at, :updated_at
json.fields record.fields
json.json_schema record.frontmatter_json_schema
