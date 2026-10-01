# frozen_string_literal: true

# A page's own fields: `schema` defines them (the same field DSL collections
# use) and `frontmatter` holds their values.
module Page::Schematized
  extend ActiveSupport::Concern

  SCHEMA_FIELD_TYPES = BlockType::COLLECTION_FIELD_TYPES

  def fields
    return [] unless schema.is_a?(Hash)

    schema["fields"] || []
  end

  # Replaces the field definitions (not their values); the whole list is
  # sent every time.
  def update_schema(fields)
    update(schema: {"fields" => fields}).tap do |saved|
      track_event(:schema_updated, path: path) if saved
    end
  end

  def update_schema!(fields)
    update_schema(fields) || raise(ActiveRecord::RecordInvalid, self)
  end

  private

  def validate_schema_shape_via_validator
    PageValidator
      .validate_schema_shape(schema, field_types: SCHEMA_FIELD_TYPES)
      .each { |msg| errors.add(:schema, msg) }
  end

  def validate_frontmatter
    PageValidator.validate_frontmatter(fields, frontmatter).each do |path, msgs|
      msgs.each { |msg| errors.add(:frontmatter, "#{path} #{msg}") }
    end
  end
end
