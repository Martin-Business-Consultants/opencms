# frozen_string_literal: true

# The field DSL's rules: validating field definitions and the data written
# against them, coercing form values, finding the references (assets, pages,
# entries) in data, collecting searchable text, and the JSON Schema published
# in the manifest. Pure logic with no records of its own, shared by block
# types, collection and page schemas, and globals.
class BlockType::Validator
  TYPES = %w[
    string text markdown code integer boolean select url datetime
    link asset record_ref record_refs repeater group blocks string_list
  ].freeze

  LINK_KINDS = %w[url page entry].freeze
  COLLECTION_FIELD_TYPES = (TYPES - %w[blocks]).freeze
  SEARCHABLE_TYPES = %w[string text markdown].freeze
  SLUG_FORMAT = /\A[a-z][a-z0-9_]*\z/
  NAME_FORMAT = /\A[a-z][a-z0-9_]*\z/
  MAX_DEPTH   = 4

  SHOW_IF_COMPARATORS = %w[equals not_equals in not_in].freeze
  SHOW_IF_PRIMITIVES  = [String, Integer, Float, TrueClass, FalseClass].freeze

  class << self
    def validate_data(fields, data)
      out = {}
      walk_validate(fields, data, "", out)
      out
    end

    def coerce_data(fields, data)
      walk_coerce(fields, data)
    end

    def each_reference_in(fields, data, &block)
      walk_refs(fields, data, &block)
    end

    def searchable_text_in(fields, data)
      out = []
      walk_text(fields, data, out)
      out.reject(&:blank?).join("\n")
    end

    def json_schema_for(fields)
      {
        "type"       => "object",
        "properties" => Array(fields).to_h { |fd| [fd["name"], field_to_json_schema(fd)] },
        "required"   => Array(fields).select { |fd| fd["required"] == true }.map { |fd| fd["name"] },
        "additionalProperties" => false
      }
    end

    def validate_fields_definition(fields, allowed_types: TYPES)
      walk_validate_fields(fields, 0, allowed_types)
    end

    private

    def walk_validate_fields(field_defs, depth, allowed_types)
      return ["nesting too deep (max #{MAX_DEPTH})"] if depth > MAX_DEPTH
      return ["must be an array"]                    unless field_defs.is_a?(Array)

      errs = []
      seen = {}

      field_defs.each_with_index do |fd, i|
        prefix = "fields[#{i}]"

        unless fd.is_a?(Hash)
          errs << "#{prefix} must be an object"
          next
        end

        name = fd["name"]
        type = fd["type"]

        if !name.is_a?(String) || !name.match?(NAME_FORMAT)
          errs << "#{prefix}.name must be lowercase snake_case"
        elsif seen[name]
          errs << "#{prefix}.name '#{name}' is duplicated"
        else
          seen[name] = true
        end

        unless allowed_types.include?(type)
          errs << "#{prefix}.type must be one of #{allowed_types.join(", ")}"
          next
        end

        case type
        when "select"
          opts = fd["options"]
          unless opts.is_a?(Array) && opts.any? && opts.all? { |o| o.is_a?(String) }
            errs << "#{prefix} (select) needs an options array of strings"
          end
        when "record_ref", "record_refs"
          oc = fd["of_collection"]
          if oc && !oc.is_a?(String)
            errs << "#{prefix} (#{type}) of_collection must be a slug string"
          end
        when "repeater", "group"
          of = fd["of"]
          if !of.is_a?(Array)
            errs << "#{prefix} (#{type}) needs an 'of' array of sub-fields"
          else
            walk_validate_fields(of, depth + 1, allowed_types).each { |e| errs << "#{prefix}.#{e}" }
          end
        when "blocks"
          allowed = fd["allowed_types"]
          if allowed && !(allowed.is_a?(Array) && allowed.all? { |s| s.is_a?(String) })
            errs << "#{prefix} (blocks) allowed_types must be an array of slugs"
          end
        end

        validate_show_if(fd["show_if"], prefix).each { |e| errs << e } if fd.key?("show_if")
      end

      errs
    end

    def validate_show_if(rule, prefix)
      return ["#{prefix}.show_if must be an object"] unless rule.is_a?(Hash)

      errs = []
      if !rule["field"].is_a?(String) || rule["field"].empty?
        errs << "#{prefix}.show_if.field must be a non-empty string"
      end

      set = SHOW_IF_COMPARATORS.select { |k| rule.key?(k) }
      if set.empty?
        errs << "#{prefix}.show_if needs one of #{SHOW_IF_COMPARATORS.join(", ")}"
      elsif set.size > 1
        errs << "#{prefix}.show_if can only set one of #{SHOW_IF_COMPARATORS.join(", ")}"
      else
        comparator = set.first
        v = rule[comparator]
        case comparator
        when "equals", "not_equals"
          unless SHOW_IF_PRIMITIVES.any? { |t| v.is_a?(t) }
            errs << "#{prefix}.show_if.#{comparator} must be a string, number, or boolean"
          end
        when "in", "not_in"
          unless v.is_a?(Array) && v.any? && v.all? { |x| SHOW_IF_PRIMITIVES.any? { |t| x.is_a?(t) } }
            errs << "#{prefix}.show_if.#{comparator} must be a non-empty array of primitives"
          end
        end
      end

      errs
    end

    def walk_coerce(field_defs, data)
      return data unless field_defs.is_a?(Array) && data.is_a?(Hash)

      result = data.dup
      field_defs.each do |fd|
        name = fd["name"]
        val  = result[name]
        next if val.nil?

        result[name] =
          case fd["type"]
          when "string", "text", "markdown", "code", "url", "asset", "record_ref"
            val.is_a?(String) ? val : val.to_s
          when "integer"
            val.is_a?(Integer) ? val : val.to_s.to_i
          when "boolean"
            next if [true, false].include?(val)
            val == 1 || val == "1" || val.to_s.downcase == "true"
          when "string_list"
            val.is_a?(Array) ? val.map { |v| v.is_a?(String) ? v : v.to_s } : val
          when "repeater"
            next unless val.is_a?(Array) && fd["of"].is_a?(Array)
            val.map { |item| item.is_a?(Hash) ? walk_coerce(fd["of"], item) : item }
          when "group"
            next unless val.is_a?(Hash) && fd["of"].is_a?(Array)
            walk_coerce(fd["of"], val)
          else
            val
          end
      end
      result
    end

    def walk_validate(field_defs, data, prefix, out)
      return unless field_defs.is_a?(Array)

      unless data.is_a?(Hash)
        (out[prefix.presence || "."] ||= []) << "must be an object"
        return
      end

      field_defs.each do |fd|
        name     = fd["name"]
        type     = fd["type"]
        required = fd["required"] == true
        val      = data[name]
        path     = prefix.empty? ? name : "#{prefix}.#{name}"

        if val.nil? || val == "" || (val.is_a?(Array) && val.empty?)
          (out[path] ||= []) << "is required" if required
          next
        end

        case type
        when "string", "text", "markdown", "code", "asset", "record_ref"
          (out[path] ||= []) << "must be a string" unless val.is_a?(String)
        when "url"
          (out[path] ||= []) << "must be a URL" unless val.is_a?(String) && !val.strip.empty?
        when "link"
          unless val.is_a?(Hash) && LINK_KINDS.include?(val["kind"]) && val["value"].is_a?(String) && !val["value"].strip.empty?
            (out[path] ||= []) << "must be { kind: url|page|entry, value: string }"
            next
          end
          if val["kind"] == "entry" && (!val["collection"].is_a?(String) || val["collection"].strip.empty?)
            (out[path] ||= []) << "kind=entry requires a collection"
          end
        when "integer"
          (out[path] ||= []) << "must be an integer" unless val.is_a?(Integer)
        when "boolean"
          (out[path] ||= []) << "must be true or false" unless [true, false].include?(val)
        when "select"
          opts = fd["options"] || []
          (out[path] ||= []) << "must be one of #{opts.join(", ")}" unless opts.include?(val)
        when "datetime"
          unless val.is_a?(String) && (Time.iso8601(val) rescue nil)
            (out[path] ||= []) << "must be an ISO 8601 datetime"
          end
        when "record_refs"
          unless val.is_a?(Array) && val.all? { |v| v.is_a?(String) && !v.empty? }
            (out[path] ||= []) << "must be an array of record slugs"
          end
        when "string_list"
          unless val.is_a?(Array) && val.all? { |v| v.is_a?(String) }
            (out[path] ||= []) << "must be an array of strings"
          end
        when "repeater"
          unless val.is_a?(Array)
            (out[path] ||= []) << "must be an array"
            next
          end
          val.each_with_index { |item, i| walk_validate(fd["of"], item, "#{path}[#{i}]", out) }
        when "group"
          unless val.is_a?(Hash)
            (out[path] ||= []) << "must be an object"
            next
          end
          walk_validate(fd["of"], val, path, out)
        when "blocks"
          unless val.is_a?(Array)
            (out[path] ||= []) << "must be an array"
            next
          end
          val.each_with_index { |block, i| validate_nested_block(block, fd, "#{path}[#{i}]", out) }
        end
      end
    end

    def validate_nested_block(block, fd, path, out)
      unless block.is_a?(Hash)
        (out[path] ||= []) << "must be an object"
        return
      end

      slug = block["type"]
      unless slug.is_a?(String)
        (out["#{path}.type"] ||= []) << "must be a string"
        return
      end

      if fd["allowed_types"].is_a?(Array) && !fd["allowed_types"].include?(slug)
        (out["#{path}.type"] ||= []) << "is not allowed here"
        return
      end

      inner = BlockType.find_by(slug: slug)
      unless inner
        (out["#{path}.type"] ||= []) << "unknown block type '#{slug}'"
        return
      end

      inner.validate_data(block["data"] || {}).each do |k, msgs|
        full = k.empty? ? "#{path}.data" : "#{path}.data.#{k}"
        (out[full] ||= []).concat(msgs)
      end
    end

    def walk_refs(field_defs, data, &block)
      return unless field_defs.is_a?(Array) && data.is_a?(Hash)

      field_defs.each do |fd|
        val = data[fd["name"]]
        next if val.nil?

        case fd["type"]
        when "asset"
          block.call(:asset, "asset", val) if val.is_a?(String) && !val.empty?
        when "record_ref"
          block.call(:record, fd["of_collection"] || "record", val) if val.is_a?(String) && !val.empty?
        when "record_refs"
          Array(val).each { |v| block.call(:record, fd["of_collection"] || "record", v) if v.is_a?(String) && !v.empty? }
        when "url"
          block.call(:link, "url", val) if val.is_a?(String) && !val.empty?
        when "link"
          next unless val.is_a?(Hash)

          v = val["value"]
          next unless v.is_a?(String) && !v.empty?

          case val["kind"]
          when "url"   then block.call(:link, "url", v)
          when "page"  then block.call(:page, "page", v)
          when "entry" then block.call(:record, val["collection"].to_s, v) if val["collection"].is_a?(String)
          end
        when "repeater"
          Array(val).each { |item| walk_refs(fd["of"], item, &block) }
        when "group"
          walk_refs(fd["of"], val, &block) if val.is_a?(Hash)
        when "blocks"
          Array(val).each do |inner|
            next unless inner.is_a?(Hash)

            inner_type = BlockType.find_by(slug: inner["type"])
            next unless inner_type

            inner_type.each_reference(inner["data"] || {}, &block)
          end
        end
      end
    end

    def walk_text(field_defs, data, out)
      return unless field_defs.is_a?(Array) && data.is_a?(Hash)

      field_defs.each do |fd|
        val = data[fd["name"]]
        next if val.nil?

        case fd["type"]
        when *SEARCHABLE_TYPES
          out << val if val.is_a?(String)
        when "string_list"
          Array(val).each { |v| out << v if v.is_a?(String) }
        when "repeater"
          Array(val).each { |item| walk_text(fd["of"], item, out) }
        when "group"
          walk_text(fd["of"], val, out) if val.is_a?(Hash)
        when "blocks"
          Array(val).each do |inner|
            next unless inner.is_a?(Hash)

            inner_type = BlockType.find_by(slug: inner["type"])
            next unless inner_type

            out << inner_type.searchable_text(inner["data"] || {})
          end
        end
      end
    end

    def field_to_json_schema(fd)
      case fd["type"]
      when "integer"     then {"type" => "integer"}
      when "boolean"     then {"type" => "boolean"}
      when "datetime"    then {"type" => "string", "format" => "date-time"}
      when "select"      then {"type" => "string", "enum" => fd["options"]}
      when "link"
        {
          "type" => "object",
          "properties" => {
            "kind"       => {"type" => "string", "enum" => LINK_KINDS},
            "value"      => {"type" => "string"},
            "collection" => {"type" => "string"}
          },
          "required" => ["kind", "value"]
        }
      when "record_refs" then {"type" => "array", "items" => {"type" => "string"}}
      when "string_list" then {"type" => "array", "items" => {"type" => "string"}}
      when "repeater"
        {
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => Array(fd["of"]).to_h { |sf| [sf["name"], field_to_json_schema(sf)] },
            "required" => Array(fd["of"]).select { |sf| sf["required"] == true }.map { |sf| sf["name"] }
          }
        }
      when "group"
        {
          "type" => "object",
          "properties" => Array(fd["of"]).to_h { |sf| [sf["name"], field_to_json_schema(sf)] },
          "required" => Array(fd["of"]).select { |sf| sf["required"] == true }.map { |sf| sf["name"] }
        }
      when "blocks"
        {
          "type"  => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "type"    => {"type" => "string"},
              "version" => {"type" => "integer"},
              "data"    => {"type" => "object"}
            },
            "required" => ["type", "data"]
          }
        }
      else {"type" => "string"}
      end
    end
  end
end
