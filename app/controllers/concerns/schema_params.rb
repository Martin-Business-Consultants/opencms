# frozen_string_literal: true

# Field-schema payloads (`schema.fields` on Page / Collection / Global, and
# `fields` on BlockType) are arbitrarily nested user-defined JSON: a field
# has options, a repeater has sub-fields, and those have their own options.
# Strong parameters can't describe that shape without enumerating every
# field type, so these payloads are unwrapped wholesale instead.
#
# That's safe here and only here: the result is assigned to a single JSON
# column, never mass-assigned onto model attributes, and the models validate
# the shape on save. Don't reach for `deep_unwrap` to permit ordinary
# attributes.
module SchemaParams
  extend ActiveSupport::Concern

  private

  def deep_unwrap(value)
    case value
    when ActionController::Parameters then deep_unwrap(value.to_unsafe_h)
    when Array                        then value.map { |v| deep_unwrap(v) }
    when Hash                         then value.transform_values { |v| deep_unwrap(v) }
    else value
    end
  end

  # Pulls `fields` out of a `{<root>: {fields: [...]}}` payload and returns
  # it as the `{schema: {"fields" => [...]}}` attribute hash the models take.
  # A missing `fields` key yields an empty list, matching the admin
  # controllers: PATCHing a schema replaces it, it doesn't merge.
  def schema_attrs_from(root)
    raw = params.dig(root, :fields)
    {schema: {"fields" => raw ? deep_unwrap(raw) : []}}
  end
end
