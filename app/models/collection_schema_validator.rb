# frozen_string_literal: true

# CollectionSchemaValidator validates the `schema` JSON shape for a Collection
# (frontmatter fields) and generates the JSON Schema for the manifest.
# Delegates core field validation to BlockType::Validator.
class CollectionSchemaValidator
  class << self
    def validate_schema_shape(schema, field_types:)
      errors = []
      unless schema.is_a?(Hash)
        errors << "must be an object"
        return errors
      end

      raw_fields = schema["fields"]
      if raw_fields && !raw_fields.is_a?(Array)
        errors << "fields must be an array"
        return errors
      end

      BlockType::Validator
        .validate_fields_definition(raw_fields || [], allowed_types: field_types)
        .each { |msg| errors << msg }

      errors
    end

    def frontmatter_json_schema(fields)
      BlockType::Validator.json_schema_for(fields)
    end
  end
end
