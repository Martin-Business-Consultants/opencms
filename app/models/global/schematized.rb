# frozen_string_literal: true

# A global's fields: `schema` defines them (the collection field DSL, without
# `blocks`) and `data` holds their values.
module Global::Schematized
  extend ActiveSupport::Concern

  def fields
    return [] unless schema.is_a?(Hash)

    schema["fields"] || []
  end

  def frontmatter_json_schema
    BlockType.json_schema_for(fields)
  end

  # Replaces the field definitions (not their values); the whole list is sent
  # every time.
  def update_schema(fields)
    update(schema: {"fields" => fields}).tap do |saved|
      track_event(:schema_updated, slug: slug) if saved
    end
  end

  def update_schema!(fields)
    update_schema(fields) || raise(ActiveRecord::RecordInvalid, self)
  end

  private

  def validate_schema_shape
    unless schema.is_a?(Hash)
      errors.add(:schema, "must be an object")
      return
    end

    raw_fields = schema["fields"]
    if raw_fields && !raw_fields.is_a?(Array)
      errors.add(:schema, "fields must be an array")
      return
    end

    BlockType
      .validate_fields_definition(raw_fields || [], allowed_types: Global::FIELD_TYPES)
      .each { |msg| errors.add(:schema, msg) }
  end

  def validate_data
    unless data.is_a?(Hash)
      errors.add(:data, "must be an object")
      return
    end

    BlockType.validate_data(fields, data).each do |path, msgs|
      msgs.each { |msg| errors.add(:data, "#{path} #{msg}") }
    end
  end
end
