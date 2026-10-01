# frozen_string_literal: true

# `record`, not `collection`: jbuilder reads a `collection:` local as a list to
# render the partial once per item.
json.extract! record, :id, :slug, :name, :enable_blocks, :schema, :build_config,
  :categories_collection_id, :tags_collection_id, :created_at, :updated_at
json.frontmatter_json_schema record.frontmatter_json_schema
json.entry_count record.entries.count
