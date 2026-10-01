# frozen_string_literal: true

# A collection's schema: the frontmatter fields every entry carries. They use
# BlockType's field DSL, and the manifest publishes them as JSON Schema.
module Collection::Schematized
  extend ActiveSupport::Concern

  # Collections share BlockType's field DSL for their frontmatter schema.
  # Entry bodies compose via `body_markdown`; a collection can additionally
  # opt into Page-style block composition by setting `enable_blocks: true`,
  # which surfaces a blocks editor on each entry (e.g. templated city pages).
  FIELD_TYPES = BlockType::COLLECTION_FIELD_TYPES

  def fields
    return [] unless schema.is_a?(Hash)

    schema["fields"] || []
  end

  def field(name)
    name = name.to_s
    return nil if name.empty?

    fields.find { |f| f["name"] == name }
  end

  # The yes/no fields, the ones an entries table can flip in place.
  def boolean_fields
    fields.select { |f| f.is_a?(Hash) && f["type"] == "boolean" }
  end

  def boolean_field(name)
    boolean_fields.find { |f| f["name"] == name.to_s }
  end

  # JSON Schema describing entry frontmatter for this collection. Exposed via
  # the manifest API.
  def frontmatter_json_schema
    CollectionSchemaValidator.frontmatter_json_schema(fields)
  end

  # Replaces the entry shape (fields, blocks switch, notifications, Build
  # board — whatever `attributes` carries) and records it.
  def change_schema(attributes)
    update(attributes).tap { |saved| track_schema_change if saved }
  end

  def change_schema!(attributes)
    update!(attributes)
    track_schema_change
  end

  private

  def track_schema_change
    track_event(:schema_updated, slug: slug)
  end

  def validate_schema_shape_via_validator
    CollectionSchemaValidator
      .validate_schema_shape(schema, field_types: FIELD_TYPES)
      .each { |msg| errors.add(:schema, msg) }
  end
end
