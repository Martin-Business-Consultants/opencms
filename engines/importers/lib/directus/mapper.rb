# frozen_string_literal: true

# Turns a SchemaScanner result into an *initial* manifest: each Directus
# collection classified (page / section / collection / global / skip),
# field-types translated to CMS field types, and best-guess BlockType +
# field mappings suggested. All suggestions are overridable in the review
# UI — this module's job is to make the common case zero-click.
#
# Pure transformation — no DB calls, no I/O. Easy to test, easy to
# reason about.
module Directus
  class Mapper
    # Directus field-type / special → CMS field type.
    # Returned as the schema FIELD type for a Collection (frontmatter) or a
    # BlockType data field. Page bodies use `blocks`, not these field types.
    TYPE_TABLE = {
      # Strings
      "string"          => "string",
      "uuid"            => "string",
      "hash"            => "string",
      "csv"             => "string",
      # Long text
      "text"            => "text",
      "markdown"        => "markdown",
      "wysiwyg"         => "markdown",
      "code"            => "text",
      # Numeric
      "integer"         => "integer",
      "bigInteger"      => "integer",
      "decimal"         => "string",   # preserve precision; CMS has no decimal field type yet
      "float"           => "string",
      # Booleans
      "boolean"         => "boolean",
      # Dates
      "date"            => "datetime",
      "dateTime"        => "datetime",
      "timestamp"       => "datetime",
      "time"            => "string",
      # JSON-ish
      "json"            => "string",   # serialized; review UI lets user remap
      "geometry"        => "string",
      # Relations — m2m/o2m fan out to nested item lists. The writer expands
      # them by walking the junction; the schema field on the CMS side is a
      # repeater. m2a is page-level "blocks" — not used as a sub-field, but
      # we map it conservatively for completeness.
      "m2m"             => "repeater",
      "o2m"             => "repeater",
      "m2a"             => "repeater",
      "m2o"             => "string",   # FK string; review UI may swap to record_ref
      "file"            => "asset",
      "files"           => "repeater",
      "translations"    => "string"
    }.freeze

    # Directus `interface` hints that override the raw type when present.
    # E.g. a `string` typed field with interface `input-rich-text-md` is
    # actually markdown content.
    INTERFACE_OVERRIDES = {
      "input-rich-text-html" => "text",
      "input-rich-text-md"   => "markdown",
      "input-code"           => "text",
      "input-multiline"      => "text",
      "select-dropdown"      => "select",
      "tags"                 => "string",
      "boolean"              => "boolean",
      "datetime"             => "datetime",
      "input-hash"           => "string"
    }.freeze

    def initialize(scan_result, existing_block_types: [], page_collection: "pages")
      @scan = scan_result
      @existing_block_types = existing_block_types  # array of {slug:, label:, fields:[FieldDef]}
      @page_collection_name = page_collection
      @relations = scan_result[:relations] || []
    end

    def call
      collections = @scan[:collections] || []
      page_coll   = collections.find { |c| c[:name] == @page_collection_name }

      section_names  = section_collection_names(page_coll)
      junction_names = detect_junctions

      classified = collections.map do |coll|
        role = classify(coll, section_names, junction_names)
        {
          directus_slug: coll[:name],
          row_count:     coll[:row_count],
          is_singleton:  coll[:is_singleton],
          role:          role,
          mapping:       build_mapping(coll, role)
        }
      end

      {
        page_collection: @page_collection_name,
        block_types_available: @existing_block_types.map { |bt| bt[:slug] },
        sections_detected: section_names,
        junctions_detected: junction_names,
        collections: classified
      }
    end

    # ----- Classification -----

    # Anything that appears as an M2A allowed-collection — anywhere in the
    # schema — is a "section" (a polymorphic block). Originally we only
    # walked pages.blocks, but Directus schemas commonly have additional M2A
    # fields on detail-page collections (e.g. team.blocks, products.blocks),
    # and their unique allowed collections need the BlockType treatment too,
    # otherwise they fall through to plain Collections and the user can't
    # render them as page blocks.
    def section_collection_names(_page_coll)
      out = []
      @relations.each do |r|
        next unless r[:one_collection_field].to_s != "" && r[:one_allowed_collections]&.any?
        out.concat(r[:one_allowed_collections])
      end
      out.uniq.reject { |n| n.to_s.empty? }
    end

    # A junction is any `many_collection` in the relations table that either:
    # * has `one_collection_field` set (it's an M2A junction), OR
    # * appears as `many_collection` in two relations, both with
    #   `junction_field` set and `one_collection` set — the canonical M2M
    #   junction shape (one relation per direction).
    def detect_junctions
      by_many = @relations.group_by { |r| r[:many_collection] }
      out = []
      by_many.each do |coll, rows|
        next if coll.to_s.empty?

        if rows.any? { |r| r[:one_collection_field].to_s != "" }
          out << coll
          next
        end
        pair = rows.select { |r| r[:junction_field].to_s != "" && r[:one_collection].to_s != "" }
        out << coll if pair.size >= 2
      end
      out.uniq
    end

    def classify(coll, section_names, junction_names)
      return "page"     if coll[:name] == @page_collection_name
      return "global"   if coll[:is_singleton]
      return "junction" if junction_names.include?(coll[:name])
      return "section"  if section_names.include?(coll[:name])
      "collection"
    end

    # ----- Per-collection mapping -----

    def build_mapping(coll, role)
      case role
      when "page"
        page_mapping(coll)
      when "section"
        section_mapping(coll)
      when "collection"
        collection_mapping(coll)
      when "global"
        global_mapping(coll)
      else
        {note: "skipped — #{role}"}
      end
    end

    # For the pages collection: figure out which field is title/slug/status,
    # which is the blocks/sections relation, and let everything else fall to
    # frontmatter.
    def page_mapping(coll)
      title_field   = pick_field(coll, %w[title name heading label])
      slug_field    = pick_field(coll, %w[slug permalink path])
      status_field  = pick_field(coll, %w[status state])
      sections_field = (coll[:fields] || []).find { |f|
        Array(f[:special]).intersect?(%w[m2a o2m m2m])
      }

      frontmatter_fields = (coll[:fields] || []).reject { |f|
        skip_field?(f) ||
          f[:name] == title_field ||
          f[:name] == slug_field ||
          f[:name] == status_field ||
          (sections_field && f[:name] == sections_field[:name])
      }.map { |f| translate_field(f) }

      {
        title_source:    title_field,
        slug_source:     slug_field,
        status_source:   status_field,
        blocks_source:   sections_field && sections_field[:name],
        frontmatter:     frontmatter_fields
      }
    end

    # Section collection → BlockType. Suggest a target slug + field map.
    def section_mapping(coll)
      target_slug = suggest_block_type_slug(coll[:name])
      target = @existing_block_types.find { |bt| bt[:slug] == target_slug }

      {
        target_block_type:    target_slug,
        target_exists:        !target.nil?,
        suggested_fields:     suggest_field_map(coll, target),
        translated_fields:    (coll[:fields] || []).reject { |f| skip_field?(f) }.map { |f| translate_field(f) }
      }
    end

    def collection_mapping(coll)
      slug = sanitize_slug(coll[:name])
      {
        cms_collection_slug: slug,
        cms_collection_name: humanize(coll[:name]),
        title_source:        pick_field(coll, %w[title name heading label]),
        slug_source:         pick_field(coll, %w[slug permalink]),
        status_source:       pick_field(coll, %w[status state]),
        body_source:         pick_field_by_type(coll, "text") || pick_field_by_interface(coll, "input-rich-text-md"),
        schema_fields:       (coll[:fields] || []).reject { |f| skip_field?(f) }.map { |f| translate_field(f) }
      }
    end

    def global_mapping(coll)
      {
        global_slug: sanitize_slug(coll[:name]),
        global_name: humanize(coll[:name]),
        schema_fields: (coll[:fields] || []).reject { |f| skip_field?(f) }.map { |f| translate_field(f) }
      }
    end

    # ----- Field translation -----

    def translate_field(f)
      cms_type = INTERFACE_OVERRIDES[f[:interface]] || TYPE_TABLE[f[:type]] || "string"
      cms_name = sanitize_field_name(f[:name])

      out = {directus_name: f[:name], cms_name: cms_name, cms_type: cms_type, directus_type: f[:type]}
      out[:required] = true if f[:required]
      out[:help]     = f[:note] if f[:note] && !f[:note].empty?

      # M2O to directus_files (Directus file FKs are uuids interfaced with file)
      if f[:type] == "uuid" && f[:interface].to_s.include?("file")
        out[:cms_type] = "asset"
      end

      # Select with predefined choices
      if f[:interface] == "select-dropdown" && f[:options].is_a?(Hash) && f[:options]["choices"]
        choices = Array(f[:options]["choices"]).map { |c| c.is_a?(Hash) ? (c["value"] || c["text"]) : c }.compact.uniq
        out[:cms_type] = "select"
        out[:options]  = choices if choices.any?
      end

      # For relational fields, record where the values live so the writer can
      # walk the junction without re-deriving it from raw relations.
      rel = lookup_relation_target(f)
      out[:relation] = rel if rel

      out
    end

    # Find the relation that backs an alias field (M2M, O2M, M2A, files).
    # Returns the junction info or nil. The writer uses this to fan out.
    def lookup_relation_target(f)
      return nil unless %w[m2m o2m m2a files].include?(f[:type])

      # Find the relation row where this field is the "one side". The
      # many_collection is the junction; for M2M, the OTHER relation off the
      # junction points to the real target collection.
      anchor = @relations.find { |r| r[:one_field] == f[:name] }
      return nil unless anchor

      junction = anchor[:many_collection]

      if f[:type] == "m2a"
        # M2A — the section list lives in one_allowed_collections on the
        # sibling relation row.
        sibling = @relations.find { |r| r[:many_collection] == junction && r[:one_collection_field] }
        return {junction: junction, kind: "m2a", allowed_collections: sibling&.[](:one_allowed_collections) || []}
      end

      # M2M — the sibling relation (different many_field) points at the real target.
      sibling = @relations.find { |r| r[:many_collection] == junction && r[:many_field] != anchor[:many_field] && r[:one_collection] }
      target = sibling&.[](:one_collection)
      kind = (f[:type] == "o2m") ? "o2m" : "m2m"
      {junction: junction, kind: kind, target: target}
    end

    # Find a field by exact name match (case-insensitive), trying preferred
    # names in order.
    def pick_field(coll, names)
      lookup = (coll[:fields] || []).each_with_object({}) { |f, h| h[f[:name].to_s.downcase] = f[:name] }
      names.each { |n| return lookup[n] if lookup[n] }
      nil
    end

    def pick_field_by_type(coll, type)
      (coll[:fields] || []).find { |f| f[:type] == type }&.[](:name)
    end

    def pick_field_by_interface(coll, interface)
      (coll[:fields] || []).find { |f| f[:interface] == interface }&.[](:name)
    end

    # Fields the CMS will always derive itself, not import.
    AUTO_FIELDS = %w[id status sort user_created user_updated date_created date_updated date_published].freeze

    def skip_field?(f)
      AUTO_FIELDS.include?(f[:name]) ||
        Array(f[:special]).include?("no-data") ||
        f[:type] == "alias" && !Array(f[:special]).intersect?(%w[m2o o2m m2m m2a translations file files])
    end

    # ----- BlockType suggestion -----

    # Walk a directus section collection name to a best-guess BlockType slug.
    # Order: exact match → strip _section/_block suffix → underscore-to-dash →
    # null (user picks).
    def suggest_block_type_slug(directus_name)
      slug = sanitize_slug(directus_name)
      base = slug.sub(/_(section|block|component)\z/, "")
      candidates = [slug, base].uniq

      have = @existing_block_types.map { |bt| bt[:slug] }
      candidates.each { |c| return c if have.include?(c) }
      # Best-effort: nil means "user must pick"
      base
    end

    # Map Directus section fields → BlockType fields by exact name match.
    # Fields without a match are emitted as suggestions with a null target.
    def suggest_field_map(coll, target_block_type)
      target_field_names = (target_block_type&.dig(:fields) || []).map { |f| f["name"] || f[:name] }

      (coll[:fields] || []).reject { |f| skip_field?(f) }.map do |f|
        sanitized = sanitize_field_name(f[:name])
        match = target_field_names.find { |n| n == sanitized } ||
                target_field_names.find { |n| n.tr("_", "") == sanitized.tr("_", "") }
        {directus_field: f[:name], target_field: match}
      end
    end

    # ----- Naming -----

    # CMS Collection.slug accepts /\A[a-z0-9][a-z0-9\-]*\z/.
    def sanitize_slug(s)
      s.to_s.downcase.gsub(/[^a-z0-9-]+/, "-").gsub(/-+/, "-").gsub(/\A-+|-+\z/, "")
    end

    # CMS field name & BlockType slug accept /\A[a-z][a-z0-9_]*\z/.
    def sanitize_field_name(s)
      base = s.to_s.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/_+/, "_").gsub(/\A_+|_+\z/, "")
      base = "f_#{base}" if base.empty? || base.match?(/\A[0-9]/)
      base
    end

    def humanize(s)
      s.to_s.tr("_-", " ").split.map(&:capitalize).join(" ")
    end

    # Roll up directus type/interface pairs that fell through to the default
    # "string". Useful for spotting things the type table should learn.
    def collect_unmapped_types(classified)
      seen = Hash.new(0)
      classified.each do |c|
        mapping = c[:mapping] || {}
        fields = (mapping[:schema_fields] || []) +
                 (mapping[:frontmatter] || []) +
                 (mapping[:translated_fields] || [])
        fields.each do |f|
          # Only flag when we fell through to the catch-all
          seen["#{f[:directus_name]}: ?"] += 1 if f[:cms_type] == "string" && f[:directus_name].to_s.match?(/\A[a-z_]+\z/)
        end
      end
      []
    end
  end
end
