# frozen_string_literal: true

require "json"

# The schema editor's form, read back into field definitions — the same
# `[{"name", "label", "type", …}]` arrays BlockType::Validator checks and
# Collection, Page, Global and BlockType store.
#
# The editor posts one row per field, keyed by an opaque id so rows can be
# added, removed and reordered in the browser without renumbering:
#
#   collection[fields][f0][name]=title
#   collection[fields][f0][type]=string
#   collection[fields][x1y2][type]=repeater
#   collection[fields][x1y2][of][z3][name]=caption
#
# Rows come back in the order they were posted, which is the order on screen.
# Only the keys the field's type uses are kept (a select's options, a
# reference's collection, a repeater's sub-fields), so switching a row's type
# doesn't leave the old type's settings behind. Keys the editor has no control
# for travel in each row's `extra` JSON and are put back untouched.
#
# An Array (a JSON API-style post) is already field definitions and passes
# through as plain Ruby.
class SchemaFields
  # Keys the editor has a control for. Anything else a field carries is `extra`.
  EDITED_KEYS = %w[name label type required help sidebar tab options of_collection allowed_types show_if of].freeze

  REFERENCE_TYPES = %w[record_ref record_refs].freeze
  NESTING_TYPES   = %w[repeater group].freeze

  class << self
    def from_params(raw)
      case raw
      when nil then []
      when Array then plain(raw)
      when ActionController::Parameters then from_rows(raw.to_unsafe_h)
      when Hash then from_rows(raw)
      else []
      end
    end

    # What a field keeps that the editor doesn't show, as the row's hidden JSON.
    def extra_json(field)
      extra = field.is_a?(Hash) ? field.except(*EDITED_KEYS) : {}
      extra.empty? ? "" : JSON.generate(extra)
    end

    # A select's options as the textarea shows them, one per line.
    def options_text(field)
      Array(field["options"]).join("\n")
    end

    def show_if_text(field)
      rule = field["show_if"]
      rule.nil? ? "" : JSON.generate(rule)
    end

    private

    def from_rows(rows)
      rows.values.filter_map { |row| field_from(row) if row.is_a?(Hash) }
    end

    def field_from(row)
      row = row.stringify_keys
      name = row["name"].to_s.strip
      type = row["type"].to_s
      return nil if name.empty? && type.empty?

      field = {"name" => name}
      field["label"] = row["label"].strip if row["label"].present?
      field["type"] = type
      field["required"] = true if checked?(row["required"])
      field["help"] = row["help"].strip if row["help"].present?
      field["sidebar"] = true if checked?(row["sidebar"])
      field["tab"] = row["tab"].strip if row["tab"].present?

      case type
      when "select"
        field["options"] = row["options"].to_s.lines.map(&:strip).reject(&:empty?)
      when *REFERENCE_TYPES
        field["of_collection"] = row["of_collection"] if row["of_collection"].present?
      when "blocks"
        allowed = Array(row["allowed_types"]).map(&:to_s).reject(&:empty?)
        field["allowed_types"] = allowed if allowed.any?
      when *NESTING_TYPES
        field["of"] = from_params(row["of"])
      end

      field["show_if"] = parse_json(row["show_if"]) if row["show_if"].present?

      extra = parse_json(row["extra"])
      extra.is_a?(Hash) ? extra.except(*EDITED_KEYS).merge(field) : field
    end

    def checked?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    # A malformed show_if stays a string so the schema's own validation names
    # it, rather than vanishing from the field.
    def parse_json(text)
      return nil if text.blank?

      JSON.parse(text)
    rescue JSON::ParserError
      text.to_s
    end

    def plain(value)
      case value
      when ActionController::Parameters then plain(value.to_unsafe_h)
      when Array then value.map { |v| plain(v) }
      when Hash then value.to_h { |k, v| [k.to_s, plain(v)] }
      else value
      end
    end
  end
end
