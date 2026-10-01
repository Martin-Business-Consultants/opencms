# frozen_string_literal: true

require "json"

# The form builder's rows, read back into a Form's `fields` — the
# `[{"name", "label", "type", …}]` array FormValidator checks and the site's
# renderer turns into inputs. The schema editor's approach (SchemaFields),
# for a form's own field shape:
#
#   form[fields][f0][name]=email
#   form[fields][f0][type]=email
#   form[fields][x1y2][type]=select
#   form[fields][x1y2][options]=general | General inquiry
#
# Rows come back in the order they were posted, which is the order on screen,
# keyed by an opaque id so rows can be added, removed and reordered without
# renumbering. Only the keys a field's type uses are kept (a select's
# options, a file field's limits), so switching a row's type doesn't leave
# the old type's settings behind. Keys the builder has no control for travel
# in each row's `extra` JSON and are put back untouched.
class FormFields
  # Keys the builder has a control for. Anything else a field carries is `extra`.
  EDITED_KEYS = %w[name label type required placeholder help default options accept multiple max_size].freeze

  # Types a person types into, which a placeholder and a default make sense for.
  TEXT_TYPES = %w[text email tel url textarea].freeze

  KB = 1024
  MB = 1024 * 1024

  class << self
    def from_params(raw)
      case raw
      when nil then []
      when Array then raw.map { |field| field.respond_to?(:to_unsafe_h) ? field.to_unsafe_h : field }
      when ActionController::Parameters then from_rows(raw.to_unsafe_h)
      when Hash then from_rows(raw)
      else []
      end
    end

    # What a field keeps that the builder doesn't show, as the row's hidden JSON.
    def extra_json(field)
      extra = field.is_a?(Hash) ? field.except(*EDITED_KEYS) : {}
      extra.empty? ? "" : JSON.generate(extra)
    end

    # A choice field's options as the textarea shows them: "value | label",
    # one per line.
    def options_text(field)
      Array(field["options"]).filter_map do |option|
        next unless option.is_a?(Hash)

        option["value"].to_s == option["label"].to_s ? option["value"].to_s : "#{option["value"]} | #{option["label"]}"
      end.join("\n")
    end

    # A file field's size cap as the input shows it: "10 MB", "500 KB", or bytes.
    def max_size_text(field)
      bytes = field["max_size"]
      return "" unless bytes.is_a?(Integer)

      if (bytes % MB).zero? then "#{bytes / MB} MB"
      elsif (bytes % KB).zero? then "#{bytes / KB} KB"
      else bytes.to_s
      end
    end

    private

    def from_rows(rows)
      rows.values.filter_map { |row| field_from(row) if row.is_a?(Hash) }
    end

    def field_from(row)
      row = row.stringify_keys
      name = row["name"].to_s.strip
      type = row["type"].to_s
      return nil if name.empty? && row["label"].to_s.strip.empty?

      field = {"name" => name}
      field["label"] = row["label"].to_s.strip
      field["type"] = type
      field["required"] = true if checked?(row["required"])
      if TEXT_TYPES.include?(type)
        field["placeholder"] = row["placeholder"].strip if row["placeholder"].present?
        field["default"] = row["default"] if row["default"].present?
      end
      field["help"] = row["help"].strip if row["help"].present?
      field["options"] = options_from(row["options"]) if FormValidator::OPTIONED_TYPES.include?(type)

      if type == "file"
        field["accept"] = row["accept"].strip if row["accept"].present?
        field["multiple"] = true if checked?(row["multiple"])
        size = max_size_from(row["max_size"])
        field["max_size"] = size if size
      end

      field.merge(extra_from(row["extra"]))
    end

    def options_from(text)
      text.to_s.lines.filter_map do |line|
        line = line.strip
        next if line.empty?

        value, label = line.split(" | ", 2).map(&:strip)
        {"value" => value, "label" => label.presence || value}
      end
    end

    # "10 MB", "500kb", "2048" → bytes; blank or unreadable → none.
    def max_size_from(text)
      match = text.to_s.strip.match(/\A(\d+(?:\.\d+)?)\s*(kb|mb|b)?\z/i) or return nil

      number = match[1].to_f
      case match[2]&.downcase
      when "mb" then (number * MB).round
      when "kb" then (number * KB).round
      else number.round
      end
    end

    def extra_from(json)
      return {} if json.blank?

      parsed = JSON.parse(json)
      parsed.is_a?(Hash) ? parsed.except(*EDITED_KEYS) : {}
    rescue JSON::ParserError
      {}
    end

    def checked?(value) = value.to_s == "1" || value == true || value.to_s == "true"
  end
end
