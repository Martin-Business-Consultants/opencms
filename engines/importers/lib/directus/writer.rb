# frozen_string_literal: true

require "sqlite3"
require "json"

# Shared helpers for the directus write pipeline. Pure functions + a SQLite
# wrapper — no Rails models touched here; each rake task pulls these helpers
# in and writes its own records.
#
# Why a helper module instead of stuffing everything into the rake file:
# - relation walking (m2m, o2m, m2a) is non-trivial and identical across
#   sections/collections/pages
# - row → frontmatter translation needs the slug-map state built progressively
#   across tasks; centralizing the file-level cache here keeps the rake stages
#   stateless and re-runnable
module Directus
  class Writer
    # Columns the CMS derives itself; never imported into frontmatter/data.
    AUTO_FIELDS = %w[id status sort user_created user_updated date_created date_updated date_published].freeze

    # Directus field names → CMS Page/CollectionEntry `seo` column keys.
    # Names are matched case-insensitively against directus_name and cms_name.
    # Order doesn't matter for keys, but values must use the canonical CMS key.
    SEO_TOP_LEVEL_MAP = {
      "meta_title"       => "meta_title",
      "seo_title"        => "meta_title",
      "meta_description" => "meta_description",
      "seo_description"  => "meta_description",
      "canonical_url"    => "canonical_url",
      "canonical"        => "canonical_url",
      "no_index"         => "noindex",
      "noindex"          => "noindex",
      "seo_no_index"     => "noindex",
      "no_follow"        => "nofollow",
      "nofollow"         => "nofollow",
      "seo_no_follow"    => "nofollow",
      "focus_keyword"    => "focus_keyword",
      "keyword"          => "focus_keyword",
      "seo_keyword"      => "focus_keyword",
      "keywords"         => "focus_keyword",
      "og_title"         => "og_title",
      "social_title"     => "og_title",
      "og_description"   => "og_description",
      "social_description" => "og_description",
      "og_type"          => "og_type",
      "schema_type"      => "schema_type",
      "twitter_card"     => "twitter_card",
      "twitter_title"    => "twitter_title",
      "twitter_description" => "twitter_description"
    }.freeze

    # Keys we recognize inside a `seo`-shaped JSON blob.
    SEO_JSON_KEY_MAP = {
      "title"            => "meta_title",
      "metatitle"        => "meta_title",
      "meta_title"       => "meta_title",
      "description"      => "meta_description",
      "metadescription"  => "meta_description",
      "meta_description" => "meta_description",
      "canonical"        => "canonical_url",
      "canonical_url"    => "canonical_url",
      "noindex"          => "noindex",
      "no_index"         => "noindex",
      "nofollow"         => "nofollow",
      "no_follow"        => "nofollow",
      "og_title"         => "og_title",
      "ogtitle"          => "og_title",
      "og_description"   => "og_description",
      "ogdescription"    => "og_description",
      "og_type"          => "og_type",
      "twitter_card"     => "twitter_card",
      "twitter_title"    => "twitter_title",
      "twitter_description" => "twitter_description",
      "focus_keyword"    => "focus_keyword",
      "keyword"          => "focus_keyword",
      "schema_type"      => "schema_type"
    }.freeze

    # Field names that ARE the seo container (a JSON blob with seo keys).
    # Matched case-insensitively against directus_name and cms_name.
    SEO_CONTAINER_NAMES = %w[seo meta metadata].freeze

    def initialize(manifest:, files_manifest: {}, slug_map: nil, warn: nil)
      @manifest        = manifest
      @files_manifest  = files_manifest || {}
      # slug_map[directus_table_name][directus_row_uuid] = cms_slug. Persisted
      # across stages via a JSON sidecar so re-running a single stage still
      # resolves refs correctly.
      @slug_map        = slug_map || {}
      @relations       = (manifest["scan"]&.dig("relations") || manifest.dig(:scan, :relations) || []).map { |r| symbolize(r) }
      @warn            = warn || ->(msg) { warn_default(msg) }
    end

    attr_reader :slug_map, :files_manifest

    def warn_default(msg)
      if defined?(Rails) && Rails.respond_to?(:logger)
        Rails.logger.warn(msg)
      else
        Kernel.warn(msg)
      end
    end

    # ----- SQLite lifecycle -----

    def with_db(db_path)
      db = SQLite3::Database.new(db_path, readonly: true)
      db.results_as_hash = true
      yield db
    ensure
      db&.close
    end

    # ----- Naming -----

    # Page/Collection/CollectionEntry slug format.
    def sanitize_slug(s)
      s.to_s.downcase.gsub(/[^a-z0-9-]+/, "-").gsub(/-+/, "-").gsub(/\A-+|-+\z/, "")
    end

    # BlockType/Global slug format (must start with a letter; underscores).
    def sanitize_identifier(s)
      base = s.to_s.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/_+/, "_").gsub(/\A_+|_+\z/, "")
      base = "x_#{base}" if base.empty? || base.match?(/\A[0-9]/)
      base
    end

    def humanize(s)
      s.to_s.tr("_-", " ").split.map(&:capitalize).join(" ")
    end

    # ----- Schema field translation -----

    # Manifest fields carry the mapper's best guess (cms_type). For relational
    # types we override here so the resulting BlockType/Collection/Global
    # schema points to a real target collection.
    def schema_field(f)
      f          = stringify(f)
      directus_t = f["directus_type"].to_s
      relation   = f["relation"] && stringify(f["relation"])

      out = {"name" => f["cms_name"], "type" => f["cms_type"]}
      out["label"] = humanize(f["directus_name"]) if f["directus_name"] && f["directus_name"] != f["cms_name"]
      # Deliberately not propagating `required` from Directus: source data
      # often contains nulls that Directus tolerated (the constraint was added
      # later, or the UI enforced it). Re-enabling required after import
      # cleanup is one click in the schema editor; failing the whole import
      # over data the writer can't synthesize isn't the right tradeoff.
      out["help"]    = f["help"] if f["help"] && !f["help"].empty?
      out["options"] = f["options"] if f["options"].is_a?(Array) && f["options"].any?

      case directus_t
      when "m2m", "o2m"
        if relation && relation["target"].to_s != ""
          out["type"]          = "record_refs"
          out["of_collection"] = sanitize_slug(relation["target"].to_s)
        else
          out["type"] = "string"
          out["help"] = ((out["help"].to_s + " ") + "[unresolved relation]").strip
        end
      when "file"
        out["type"] = "asset"
      when "files"
        # Directus 'files' is M2M to directus_files; binaries aren't imported,
        # so a string FK list is the most honest representation. The review UI
        # lets the user swap it out later.
        out["type"] = "string"
        out["help"] = ((out["help"].to_s + " ") + "[Directus 'files' field — assets not imported]").strip
      when "m2a"
        # Only legitimate as page.blocks — handled separately. Anywhere else
        # (rare) we degrade to string.
        out["type"] = "string"
        out["help"] = ((out["help"].to_s + " ") + "[M2A field outside page body]").strip
      when "json"
        # JSON values are stored as serialized strings in Directus; CMS has no
        # native JSON field yet, so represent as a multi-line text.
        out["type"] = "text"
      when "uuid"
        # `file` interface on a uuid is treated as asset by the mapper already.
        out["type"] = "asset" if out["type"] == "asset"
      end

      out
    end

    # Translate a row of a Directus table into a CMS frontmatter/data hash.
    # `mappings` is the manifest's translated_fields / schema_fields list.
    # `skip_refs:` makes the call cheap on the first pass — record_refs fields
    # need the slug_map fully populated to resolve, so we write entries in
    # two passes (PASS A: scalars only, PASS B: refs only, merged).
    # `only_refs:` is the inverse — used in PASS B.
    def translate_row(db, row, mappings, skip_refs: false, only_refs: false)
      out = {}
      mappings.each do |fm|
        fm        = stringify(fm)
        directus  = fm["directus_name"]
        cms_name  = fm["cms_name"]
        directus_t = fm["directus_type"].to_s
        relation  = fm["relation"] && stringify(fm["relation"])
        is_ref = %w[m2m o2m].include?(directus_t)
        next if skip_refs && is_ref
        next if only_refs && !is_ref

        value =
          case directus_t
          when "m2m", "o2m"
            resolve_refs(db, row, fm, relation)
          when "file"
            # Asset references won't resolve (no binaries imported); leave
            # blank but keep the field present so the schema validates.
            nil
          when "files"
            ids = resolve_refs(db, row, fm, relation)
            ids.is_a?(Array) ? ids.join(",") : nil
          when "boolean"
            raw = row[directus]
            raw.nil? ? nil : (raw == 1 || raw == true || raw == "1" || raw.to_s.downcase == "true")
          when "integer"
            raw = row[directus]
            raw.nil? || raw == "" ? nil : raw.to_i
          when "json"
            raw = row[directus]
            raw.to_s
          when "date", "dateTime", "timestamp"
            coerce_datetime(row[directus])
          else
            row[directus]
          end

        # Drop nils/empties so the CMS doesn't store noise.
        next if value.nil? || value == "" || value == []

        out[cms_name] = value
      end
      out
    end

    # Pluck SEO-related values out of a row before the rest goes to
    # frontmatter. Returns [seo_hash, consumed_cms_names_set]. The page /
    # collection-entry writer puts seo_hash on the dedicated `seo` JSON
    # column and skips any field whose cms_name is in the consumed set
    # when building frontmatter.
    #
    # Two sources are recognized:
    #   1. A JSON-typed field named `seo` / `meta` / `metadata` — keys inside
    #      get mapped via SEO_JSON_KEY_MAP.
    #   2. Top-level fields whose name matches SEO_TOP_LEVEL_MAP (e.g.
    #      `meta_title`, `no_index`, `canonical_url`).
    # When both exist, top-level fields override the JSON blob — they're the
    # more explicit signal.
    def extract_seo(row, mappings)
      seo = {}
      consumed = []

      # Pass 1: JSON containers
      mappings.each do |fm|
        fm = stringify(fm)
        name_d = fm["directus_name"].to_s
        name_c = fm["cms_name"].to_s
        next unless fm["directus_type"].to_s == "json" &&
                    (SEO_CONTAINER_NAMES.include?(name_d.downcase) || SEO_CONTAINER_NAMES.include?(name_c.downcase))
        consumed << name_c
        parsed = parse_seo_payload(row[name_d])
        next unless parsed.is_a?(Hash)
        parsed.each do |k, v|
          next if v.nil? || v == "" || v == []
          cms_key = SEO_JSON_KEY_MAP[k.to_s.downcase.delete("_")] || SEO_JSON_KEY_MAP[k.to_s.downcase]
          next unless cms_key
          seo[cms_key] = coerce_seo_value(cms_key, v)
        end
      end

      # Pass 2: explicit top-level fields (override the JSON blob)
      mappings.each do |fm|
        fm = stringify(fm)
        name_d = fm["directus_name"].to_s.downcase
        name_c = fm["cms_name"].to_s.downcase
        cms_key = SEO_TOP_LEVEL_MAP[name_d] || SEO_TOP_LEVEL_MAP[name_c]
        next unless cms_key
        consumed << fm["cms_name"].to_s
        v = row[fm["directus_name"]]
        next if v.nil? || v == ""
        seo[cms_key] = coerce_seo_value(cms_key, v)
      end

      [seo.compact, consumed.uniq]
    end

    # Heuristic: is this mapping a field we'll fold into the seo column?
    # Used by collection schema builder to keep these fields OUT of the
    # Collection.schema (since they're edited via the dedicated SEO panel,
    # not as regular frontmatter fields).
    def seo_field?(fm)
      fm = stringify(fm)
      name_d = fm["directus_name"].to_s.downcase
      name_c = fm["cms_name"].to_s.downcase
      return true if fm["directus_type"].to_s == "json" &&
                     (SEO_CONTAINER_NAMES.include?(name_d) || SEO_CONTAINER_NAMES.include?(name_c))
      SEO_TOP_LEVEL_MAP.key?(name_d) || SEO_TOP_LEVEL_MAP.key?(name_c)
    end

    # Walk an m2m/o2m relation for one row. Returns array of CMS slugs (the
    # @slug_map must already contain target rows; run collection entries
    # before sections/pages so this resolves).
    def resolve_refs(db, row, fm, relation)
      return [] unless relation && relation["target"].to_s != ""

      target_table = relation["target"]
      junction     = relation["junction"]
      kind         = relation["kind"]
      directus     = fm["directus_name"]

      # Find the parent relation row to learn the FK columns.
      parent_rel = @relations.find { |r| r[:one_field].to_s == directus.to_s && r[:many_collection].to_s == junction.to_s }
      return [] unless parent_rel

      parent_fk = parent_rel[:many_field]

      target_ids =
        if kind == "o2m"
          # No junction: the "many" table itself holds the FK.
          rows = safe_exec(db, "SELECT id FROM #{q(junction)} WHERE #{q(parent_fk)} = ?", [row["id"]])
          rows.map { |r| r["id"] }
        else
          target_fk = parent_rel[:junction_field]
          if target_fk.to_s.empty?
            sibling = @relations.find { |r| r[:many_collection] == junction && r[:many_field] != parent_fk }
            target_fk = sibling&.[](:many_field)
          end
          return [] if target_fk.to_s.empty?
          rows = safe_exec(db, "SELECT #{q(target_fk)} AS tid FROM #{q(junction)} WHERE #{q(parent_fk)} = ?", [row["id"]])
          rows.map { |r| r["tid"] }
        end

      target_ids.compact.filter_map { |tid| @slug_map.dig(target_table, tid) }
    end

    # Walk the M2A pages → blocks junction. Returns ordered list of
    # {collection, item, sort} for a given page UUID. Caller decides which of
    # those have a known BlockType and synthesizes the page's blocks array.
    def walk_m2a_for_page(db, page_collection, blocks_field, page_id)
      anchor = @relations.find { |r| r[:one_collection] == page_collection && r[:one_field] == blocks_field }
      return [] unless anchor

      junction = anchor[:many_collection]
      parent_fk = anchor[:many_field]
      item_col  = anchor[:junction_field]
      coll_col  = collection_marker_column(junction)

      return [] unless item_col && coll_col

      sort_clause = column_exists?(db, junction, "sort") ? " ORDER BY sort" : ""
      rows = safe_exec(db,
        "SELECT #{q(coll_col)} AS collection, #{q(item_col)} AS item, " \
        "#{column_exists?(db, junction, "sort") ? "sort" : "NULL AS sort"} " \
        "FROM #{q(junction)} WHERE #{q(parent_fk)} = ?#{sort_clause}", [page_id])
      rows
    end

    # The sibling relation row carries the m2a polymorphic collection marker.
    def collection_marker_column(junction)
      sibling = @relations.find { |r| r[:many_collection] == junction && r[:one_collection_field].to_s != "" }
      sibling&.[](:one_collection_field)
    end

    # ----- Slug + title synthesis for collections that lack them -----

    # Pick the most useful "title source" from a row: an explicit title-ish
    # field, or the first non-empty string field, or "Untitled".
    def synthesize_title(row, mappings)
      title_candidates = mappings.select { |fm|
        fm = stringify(fm)
        %w[title name heading label question].include?(fm["cms_name"]) ||
          %w[string text markdown wysiwyg].include?(fm["directus_type"].to_s)
      }
      title_candidates.each do |fm|
        v = row[stringify(fm)["directus_name"]].to_s.strip
        return truncate(v, 120) if v != "" && !v.match?(/\A\h{8}-\h{4}-/)
      end
      "Untitled"
    end

    # Unique-within-collection slug. We use the Directus UUID's first segment
    # plus a slugified hint when one is available, so re-imports are stable.
    def synthesize_slug(row, hint_title)
      uid = row["id"].to_s
      tail = uid.split("-").first.to_s[0, 8]
      tail = uid.delete("^a-z0-9")[0, 8] if tail.empty?
      tail = SecureRandom.hex(4) if tail.empty?
      head = sanitize_slug(hint_title.to_s)[0, 40]
      head = "" if head =~ /\A-*\z/
      head.empty? ? tail : "#{head}-#{tail}"
    end

    # Directus stores a `seo` field as JSON text in SQLite — sometimes
    # nested under a top-level "seo" key, sometimes flat. Tolerate both.
    def parse_seo_payload(raw)
      return raw if raw.is_a?(Hash)
      return {} if raw.nil? || raw.to_s == ""
      v = JSON.parse(raw.to_s)
      # If the user wrapped it as `{"seo": {...}}` (rare but seen), unwrap.
      v.is_a?(Hash) && v.size == 1 && v.keys.first.to_s.downcase == "seo" ? v.values.first : v
    rescue JSON::ParserError
      {}
    end

    # Booleans need to be real booleans for the SEO panel's switch UI;
    # everything else is stored as a string. Asset references (og image)
    # would need an asset_id, but we don't import binaries — those keys
    # are dropped here rather than stored as broken UUIDs.
    def coerce_seo_value(cms_key, v)
      case cms_key
      when "noindex", "nofollow"
        v == true || v == 1 || v == "1" || v.to_s.downcase == "true"
      else
        v.to_s.strip
      end
    end

    # Directus stores dates inconsistently in SQLite: as epoch milliseconds
    # (Knex's default for JS Date), as "YYYY-MM-DD" strings, or already-ISO.
    # The CMS datetime validator wants ISO 8601 — normalize all three here.
    def coerce_datetime(v)
      return nil if v.nil? || v == ""
      if v.is_a?(Numeric)
        # Heuristic: 10-digit = seconds, 13-digit = milliseconds.
        secs = v.to_i.abs >= 10**12 ? v.to_i / 1000 : v.to_i
        return Time.at(secs).utc.iso8601
      end
      s = v.to_s.strip
      # Bare date "YYYY-MM-DD" → midnight UTC.
      return "#{s}T00:00:00Z" if s =~ /\A\d{4}-\d{2}-\d{2}\z/
      # "YYYY-MM-DD HH:MM:SS" (Directus SQLite default for timestamps) → ISO.
      return s.tr(" ", "T") + "Z" if s =~ /\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\z/
      # Otherwise trust it — Time.parse + iso8601 to normalize, fall back to raw.
      Time.parse(s).utc.iso8601
    rescue ArgumentError
      nil
    end

    # Truncate without splitting mid-word.
    def truncate(s, max)
      return s if s.length <= max
      cut = s[0, max].rpartition(" ").first
      (cut.empty? ? s[0, max] : cut).strip
    end

    # ----- SQLite helpers -----

    def column_exists?(db, table, col)
      db.execute("PRAGMA table_info(#{q(table)})").any? { |r| r["name"] == col }
    rescue SQLite3::Exception
      false
    end

    def column_names(db, table)
      db.execute("PRAGMA table_info(#{q(table)})").map { |r| r["name"] }
    rescue SQLite3::Exception
      []
    end

    def table_exists?(db, name)
      db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1", [name]).any?
    rescue SQLite3::Exception
      false
    end

    def safe_exec(db, sql, params = [])
      db.execute(sql, params)
    rescue SQLite3::Exception => e
      @warn.call("[Directus::Writer] sql failed: #{e.message} — #{sql}")
      []
    end

    def q(ident)
      %("#{ident.to_s.gsub('"', '""')}")
    end

    # ----- Slug map persistence (JSON sidecar in dest_dir) -----

    SLUG_MAP_FILENAME = "directus-slug-map.json"

    def self.load_slug_map(dest_dir)
      path = File.join(dest_dir, SLUG_MAP_FILENAME)
      File.exist?(path) ? JSON.parse(File.read(path)) : {}
    end

    def self.save_slug_map(dest_dir, slug_map)
      path = File.join(dest_dir, SLUG_MAP_FILENAME)
      File.write(path, JSON.pretty_generate(slug_map))
    end

    def record_slug(directus_table, directus_id, cms_slug)
      @slug_map[directus_table] ||= {}
      @slug_map[directus_table][directus_id] = cms_slug
    end

    private

    def stringify(h)
      return h if h.nil?
      return h if h.is_a?(String)
      return h if h.is_a?(Array)
      h.each_with_object({}) { |(k, v), o| o[k.to_s] = v }
    end

    def symbolize(h)
      return h if h.nil?
      h.each_with_object({}) { |(k, v), o| o[k.to_sym] = v }
    end
  end
end
