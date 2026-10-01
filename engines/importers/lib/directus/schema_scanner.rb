# frozen_string_literal: true

require "sqlite3"
require "json"

# Reads a Directus SQLite export and produces a structured snapshot of its
# schema: which collections exist, what fields each has, what relations
# connect them, row counts. No Rails models, no writes — runs against the
# uploaded file synchronously so the controller can render a review UI
# before the write pipeline is enqueued.
#
# Tested against Directus 10/11 SQLite exports. The shape of system tables
# has shifted between versions; this scanner reads the table layout via
# PRAGMA before querying, so missing columns are tolerated.
module Directus
  class SchemaScanner
    # Tables that are Directus internals; not user content. Anything else in
    # the `directus_collections` table is treated as user-defined.
    SYSTEM_PREFIX = "directus_"

    # `directus_collections.collection` rows that have no underlying SQLite
    # table — these are pure folder/group metadata in the admin UI. We skip
    # them. (Detected dynamically, but listed here for clarity.)
    KNOWN_NON_TABLE_META = %w[].freeze

    def initialize(db_path)
      @db_path = db_path
      @warnings = []
    end

    def call
      open_db do |db|
        relations = scan_relations(db)
        {
          source_file:      File.basename(@db_path),
          size_bytes:       File.size(@db_path),
          directus_version: detect_version(db),
          tables_total:     count_all_tables(db),
          collections:      scan_collections(db, relations),
          relations:        relations,
          files:            scan_files_summary(db),
          settings:         scan_settings_summary(db),
          users:            scan_users_summary(db),
          warnings:         @warnings
        }
      end
    end

    private

    def open_db
      # mode: readonly so we can't accidentally mutate the upload.
      db = SQLite3::Database.new(@db_path, readonly: true)
      db.results_as_hash = true
      yield db
    ensure
      db&.close
    end

    # Highest applied migration version, if `directus_migrations` is present.
    def detect_version(db)
      return nil unless table_exists?(db, "directus_migrations")

      row = db.execute("SELECT version FROM directus_migrations ORDER BY version DESC LIMIT 1").first
      row && row["version"]
    rescue SQLite3::Exception => e
      @warnings << "version detect failed: #{e.message}"
      nil
    end

    def count_all_tables(db)
      db.execute("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table'").first["n"]
    end

    # ----- Collections -----

    def scan_collections(db, relations)
      return [] unless table_exists?(db, "directus_collections")

      coll_cols = column_names(db, "directus_collections")
      select_cols = %w[collection singleton hidden note icon].select { |c| coll_cols.include?(c) }
      rows = db.execute("SELECT #{select_cols.map { |c| quote_ident(c) }.join(", ")} FROM directus_collections WHERE collection NOT LIKE 'directus_%' ORDER BY collection")

      directus_field_rows = scan_fields_raw(db)
      by_many = relations.group_by { |r| r[:many_collection] }
      by_one  = relations.group_by { |r| r[:one_collection] }

      rows.filter_map do |row|
        name = row["collection"]
        unless table_exists?(db, name)
          # Folder/group entries in directus_collections without an underlying
          # table — skipped, but logged so the user knows.
          @warnings << "directus_collections row '#{name}' has no underlying table — skipped"
          next
        end

        sql_types = column_sql_types(db, name)
        field_rows = directus_field_rows[name] || []

        {
          name:          name,
          is_singleton:  truthy?(row["singleton"]),
          is_hidden:     truthy?(row["hidden"]),
          note:          row["note"],
          icon:          row["icon"],
          row_count:     safe_row_count(db, name),
          column_count:  sql_types.size,
          fields:        build_fields(field_rows, sql_types),
          relations_out: by_many[name] || [],
          relations_in:  by_one[name]  || []
        }
      end
    end

    # Per-field record merging directus_fields metadata + the actual SQL
    # column type from PRAGMA. A field may exist in directus_fields without a
    # SQL column (M2A/O2M virtual aliases) — in that case we infer the type
    # purely from `special`.
    def build_fields(field_rows, sql_types)
      seen = {}
      out = field_rows.map do |row|
        seen[row[:name]] = true
        type = derive_type(row[:special], row[:interface], sql_types[row[:name]])
        row.merge(type: type, sql_type: sql_types[row[:name]])
      end
      # Some columns may exist in the table but have no directus_fields row
      # (rare — usually auto-managed system columns). Surface them as raw.
      sql_types.each do |col, sql|
        next if seen[col]
        out << {
          name: col, type: derive_type([], nil, sql), sql_type: sql,
          special: [], interface: nil, options: nil, note: nil,
          required: false, readonly: false, hidden: false, synthetic: true
        }
      end
      out
    end

    # Read directus_fields into a hash { collection_name => [raw_field, ...] }.
    # The `type` here is the logical type; the actual column SQL type is read
    # separately via PRAGMA so we work on Directus schemas that store no
    # `type` column in directus_fields (older / migrated DBs).
    def scan_fields_raw(db)
      return {} unless table_exists?(db, "directus_fields")

      cols = column_names(db, "directus_fields")
      wanted = %w[collection field special interface options note required readonly hidden sort group].select { |c| cols.include?(c) }
      rows = db.execute("SELECT #{wanted.map { |c| quote_ident(c) }.join(", ")} FROM directus_fields ORDER BY collection, COALESCE(sort, 999), field")

      grouped = Hash.new { |h, k| h[k] = [] }
      rows.each do |row|
        coll = row["collection"]
        next if coll.to_s.start_with?(SYSTEM_PREFIX)

        grouped[coll] << {
          name:      row["field"],
          # `special` is a CSV in Directus (e.g. "uuid", "json", "m2o,user-created").
          special:   csv(row["special"]),
          interface: row["interface"],
          options:   parse_json(row["options"]),
          note:      row["note"],
          required:  truthy?(row["required"]),
          readonly:  truthy?(row["readonly"]),
          hidden:    truthy?(row["hidden"])
        }
      end
      grouped
    end

    # Return the relations table as an array of hashes — the canonical form.
    # Callers group as needed.
    def scan_relations(db)
      return [] unless table_exists?(db, "directus_relations")

      cols = column_names(db, "directus_relations")
      wanted = %w[many_collection many_field one_collection one_field one_collection_field one_allowed_collections junction_field].select { |c| cols.include?(c) }
      rows = db.execute("SELECT #{wanted.map { |c| quote_ident(c) }.join(", ")} FROM directus_relations")

      rows.map do |row|
        {
          many_collection:         row["many_collection"],
          many_field:              row["many_field"],
          one_collection:          row["one_collection"],
          one_field:               row["one_field"],
          one_collection_field:    row["one_collection_field"],
          one_allowed_collections: csv(row["one_allowed_collections"]),
          junction_field:          row["junction_field"]
        }
      end
    end

    # Derive a logical type from (special CSV, interface, SQL column type).
    # Precedence: relational/file `special` markers → JSON/UUID specials →
    # interface hints → SQL type → fall back to "string".
    def derive_type(special, interface, sql_type)
      special = Array(special)

      return "m2a"          if special.include?("m2a")
      return "m2o"          if special.include?("m2o")
      return "o2m"          if special.include?("o2m")
      return "m2m"          if special.include?("m2m")
      return "file"         if special.include?("file")
      return "files"        if special.include?("files")
      return "translations" if special.include?("translations")
      return "json"         if special.include?("json")
      return "csv"          if special.include?("csv")
      return "uuid"         if special.include?("uuid")
      return "hash"         if special.include?("hash")

      case interface
      when "input-rich-text-md"   then return "markdown"
      when "input-rich-text-html" then return "wysiwyg"
      when "input-code"           then return "code"
      when "datetime"             then return "dateTime"
      when "boolean"              then return "boolean"
      when "tags"                 then return "tags"
      when "select-dropdown"      then return "select"
      end

      sql_to_type(sql_type)
    end

    # Normalize a SQLite column type ("varchar(64)", "char(36)", "timestamp",
    # "integer", "boolean", "text", "json", "real") into the same logical
    # vocabulary Directus uses. Conservative: unknown SQL types fall through
    # to "string" so the mapper at least handles them as text.
    def sql_to_type(sql)
      return "alias" if sql.nil? || sql == ""

      s = sql.to_s.downcase
      case s
      when /\Aint/, /\Abigint/         then "integer"
      when /\Aboolean/                 then "boolean"
      when /\Areal/, /\Afloat/, /\Adouble/, /\Adecimal/, /\Anumeric/ then "decimal"
      when /\Adate(\z|time)/, /timestamp/ then "dateTime"
      when /\Atime\z/                  then "time"
      when /\Ajson/                    then "json"
      when /\Achar\(36\)/              then "uuid"
      when /\Achar/, /\Avarchar/       then "string"
      when /\Atext/                    then "text"
      when /\Ablob/                    then "binary"
      else "string"
      end
    end

    # ----- Side summaries (files, settings, users) -----

    def scan_files_summary(db)
      return {present: false} unless table_exists?(db, "directus_files")

      total = safe_row_count(db, "directus_files")
      # Sample a few rows to hint at storage layout — purely informational.
      sample = db.execute("SELECT filename_disk, type, filesize FROM directus_files LIMIT 3") rescue []
      {present: true, count: total, sample: sample}
    end

    def scan_settings_summary(db)
      return {present: false} unless table_exists?(db, "directus_settings")

      row = db.execute("SELECT * FROM directus_settings LIMIT 1").first
      {present: true, has_row: !row.nil?, keys: row ? row.keys.reject { |k| k.is_a?(Integer) } : []}
    end

    def scan_users_summary(db)
      return {present: false} unless table_exists?(db, "directus_users")

      {present: true, count: safe_row_count(db, "directus_users")}
    end

    # ----- SQLite helpers -----

    def table_exists?(db, name)
      db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1", [name]).any?
    end

    def column_names(db, table)
      db.execute("PRAGMA table_info(#{quote_ident(table)})").map { |r| r["name"] }
    end

    # { column_name => sql_type_string }. Used to derive logical field types
    # when directus_fields lacks a `type` column.
    def column_sql_types(db, table)
      db.execute("PRAGMA table_info(#{quote_ident(table)})").each_with_object({}) do |row, h|
        h[row["name"]] = row["type"]
      end
    end

    def safe_row_count(db, table)
      db.execute("SELECT COUNT(*) AS n FROM #{quote_ident(table)}").first["n"]
    rescue SQLite3::Exception => e
      @warnings << "row count failed for #{table}: #{e.message}"
      nil
    end

    # SQLite identifier quoting — double quotes, embedded quotes doubled.
    def quote_ident(name)
      %("#{name.to_s.gsub('"', '""')}")
    end

    def truthy?(v)
      v == 1 || v == true || v == "1" || v == "true"
    end

    def csv(v)
      return [] if v.nil? || v == ""

      v.is_a?(Array) ? v : v.to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def parse_json(v)
      return nil if v.nil? || v == ""

      JSON.parse(v)
    rescue JSON::ParserError
      v # leave as-is if it isn't actually JSON
    end
  end
end
