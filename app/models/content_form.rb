# frozen_string_literal: true

# Reads the content editor's form back into the JSON a page, entry or global
# stores: frontmatter and global data (an object of schema fields), and block
# lists. The form is rendered by ContentFormHelper.
#
# The rule that keeps untouched content byte-identical: every object carries
# the value it was rendered from (a block and a repeater item post it as
# `_original`; everything else gets it from its parent), and a field whose
# posted value is equivalent to that original keeps the original exactly —
# its type, its absence, its key order. Keys the schema doesn't declare are
# carried over untouched. So a form saved without edits writes back what it
# read, and an edit changes only the fields it touched.
#
# Lists (blocks, repeater items, string lists, record refs) post as a hash of
# opaque keys in document order plus a `_list` marker, so an emptied list
# still arrives; a field that doesn't arrive at all keeps its original.
module ContentForm
  LIST_MARKER = "_list"
  ORIGINAL = "_original"

  class InvalidJson < StandardError
    attr_reader :path

    def initialize(path, message)
      @path = path
      super("#{path} is not valid JSON (#{message})")
    end
  end

  module_function

  # One object of schema fields. `original` is the stored value it was
  # rendered from (a Hash, or nil for a new one).
  def object(fields, submitted, original:, block_types:, path: nil)
    original = original.is_a?(Hash) ? original.deep_stringify_keys : {}
    submitted = plain(submitted)
    return original unless submitted.is_a?(Hash)

    decoded = {}
    Array(fields).each do |field|
      name = field["name"].to_s
      next if name.empty?

      if submitted.key?(name)
        value = field_value(field, submitted[name], original, block_types:, path: [path, name].compact.join("."))
        decoded[name] = value unless value.equal?(OMIT)
      elsif original.key?(name)
        decoded[name] = original[name]
      end
    end

    in_original_order(original, decoded, keep_extras: true)
  end

  # A block list. `submitted` is the list's hash of rows; each row carries its
  # own `_original`.
  def blocks(submitted, block_types:)
    rows(submitted).map { |row| block(row, block_types:) }
  end

  def block(row, block_types:)
    original = parse_json(row[ORIGINAL]) || {}
    return parse_json(row["_json"]) || original if row.key?("_json")

    type = row["type"].to_s
    block_type = block_types[type]
    decoded = {
      "id" => keep(original["id"], row["id"].to_s),
      "type" => type,
      "version" => version(original["version"], row["version"])
    }
    # A block written without an id or version (a page template's) keeps
    # lacking them rather than gaining empty ones.
    decoded.delete("id") if decoded["id"].blank? && !original.key?("id")
    decoded.delete("version") if decoded["version"].nil? && !original.key?("version")

    data_original = original["data"].is_a?(Hash) ? original["data"] : nil
    data = if block_type
      object(block_type.fields, row["data"] || {}, original: data_original, block_types:)
    else
      data_original || {}
    end
    decoded["data"] = data unless data.empty? && !original.key?("data")

    in_original_order(original, decoded, keep_extras: true)
  end

  OMIT = Object.new.freeze

  def field_value(field, raw, original, block_types:, path:)
    name = field["name"].to_s
    had = original.key?(name)
    before = original[name]

    value = case field["type"]
    when "integer" then integer(raw)
    when "boolean" then ActiveModel::Type::Boolean.new.cast(scalar(raw)) || false
    when "datetime" then datetime(scalar(raw))
    when "link" then link(raw)
    when "string_list", "record_refs" then rows(raw).map { scalar(it) }
    when "repeater" then rows(raw).map { |item| object(field["of"], item, original: parse_json(plain(item)[ORIGINAL]), block_types:) }
    when "group" then object(field["of"], raw, original: before, block_types:, path:)
    when "blocks" then blocks(raw, block_types:)
    when "json" then json(raw, path:)
    when "markdown", "plain_text", "code" then text(scalar(raw))
    else scalar(raw)
    end

    if had && equivalent?(field["type"], before, value)
      before
    elsif !had && blank_value?(value)
      OMIT
    else
      value
    end
  end

  # "Nothing entered": what a field the stored object lacked may post without
  # the author having typed anything.
  def blank_value?(value)
    value.nil? || value == false || (value.respond_to?(:empty?) && value.empty?)
  end

  def equivalent?(type, before, after)
    case type
    when "integer" then before.to_s == after.to_s || (before.nil? && after.nil?)
    when "boolean" then (before ? true : false) == after
    when "datetime" then same_time?(before, after)
    when "repeater", "group", "blocks", "link", "string_list", "record_refs", "json" then normalized(before) == normalized(after)
    else before.to_s == after.to_s
    end
  end

  # A textarea posts its line breaks as CRLF; stored text uses LF, so an
  # untouched value compares equal and a changed one is stored the same way.
  def text(value)
    value.is_a?(String) ? value.gsub("\r\n", "\n") : value
  end

  # The same second: the input shows seconds but not fractions of one, so an
  # untouched "…:20.123Z" posts back as "…:20" and is still the same time.
  def same_time?(before, after)
    return true if before.blank? && after.blank?
    return false if before.blank? || after.blank?

    Time.iso8601(before.to_s).to_i == Time.iso8601(after.to_s).to_i
  rescue ArgumentError
    before.to_s == after.to_s
  end

  # A datetime-local value ("2026-10-01T09:30"), typed in the site's zone
  # (Time.zone during the request), as the ISO string in UTC the field
  # stores. An ISO value with its own offset keeps it; anything else is kept
  # as typed.
  def datetime(text)
    text = text.to_s.strip
    return nil if text.empty?

    Time.zone.parse(text)&.utc&.iso8601(3) || text
  rescue ArgumentError
    text
  end

  # Hash key order doesn't make two values different.
  def normalized(value)
    case value
    when Hash then value.to_h { |k, v| [k.to_s, normalized(v)] }.sort.to_h
    when Array then value.map { normalized(it) }
    when nil then nil
    else value
    end
  end

  def integer(raw)
    text = scalar(raw).to_s.strip
    return nil if text.empty?

    Integer(text, 10)
  rescue ArgumentError
    text
  end

  def version(before, raw)
    return before if raw.nil? || before.to_s == raw.to_s

    integer(raw)
  end

  def link(raw)
    raw = plain(raw)
    return nil unless raw.is_a?(Hash)

    kind = raw["kind"].to_s
    case kind
    when "url"
      value = raw["url"].to_s.strip
      value.empty? ? nil : {"kind" => "url", "value" => value}
    when "page"
      value = raw["page"].to_s
      value.empty? ? nil : {"kind" => "page", "value" => value}
    when "entry"
      collection, value = raw["entry"].to_s.split("/", 2)
      value.blank? ? nil : {"kind" => "entry", "collection" => collection, "value" => value}
    end
  end

  def json(raw, path:)
    text = scalar(raw).to_s
    return nil if text.strip.empty?

    JSON.parse(text)
  rescue JSON::ParserError => e
    raise InvalidJson.new(path, e.message.lines.first.to_s.strip)
  end

  # The posted rows of a list, in document order, without the marker.
  def rows(raw)
    raw = plain(raw)
    case raw
    when Hash then raw.except(LIST_MARKER).values
    when Array then raw
    else []
    end
  end

  def scalar(raw)
    raw.is_a?(Array) ? raw.last : raw
  end

  def keep(before, after)
    before.to_s == after ? before : after
  end

  def parse_json(text)
    return nil if text.blank?

    JSON.parse(text.to_s)
  rescue JSON::ParserError
    nil
  end

  # Decoded keys in the order the stored object had them, then new ones. A
  # stored key missing from `decoded` is one the schema doesn't declare (a
  # declared key the object had always decodes to something), so it's kept.
  def in_original_order(original, decoded, keep_extras:)
    out = {}
    original.each_key do |key|
      if decoded.key?(key)
        out[key] = decoded[key]
      elsif keep_extras
        out[key] = original[key]
      end
    end
    decoded.each { |key, value| out[key] = value unless out.key?(key) }
    out
  end

  def plain(value)
    case value
    when ActionController::Parameters then value.to_unsafe_h.to_h
    when ActiveSupport::HashWithIndifferentAccess then value.to_h
    else value
    end
  end
end
