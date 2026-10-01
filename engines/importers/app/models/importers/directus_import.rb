# frozen_string_literal: true

require "fileutils"
require "json"
require "sqlite3"

module Importers
  # One Directus SQLite export into this site, in stages:
  #
  #   import = Importers::DirectusImport.new(db_path, dest_dir)
  #   import.scan         # directus-manifest.json (schema only, no writes)
  #   import.files        # directus-files-manifest.json (metadata; no binaries)
  #   import.collections  # Collections + entries, two passes so refs resolve
  #   import.block_types  # one BlockType per section collection
  #   import.globals      # singletons
  #   import.pages        # pages, one block per M2A section row
  #   import.all          # scan if needed, then every stage in that order
  #
  # Write order is deliberate: collections come first because everything else
  # may reference their entries by slug; block types and globals only carry
  # schemas; pages walk the M2A junction last. Each stage reads the sidecar
  # files the earlier ones wrote into dest_dir, so a stage re-runs on its own.
  #
  # Progress goes to `out` and problems to `err` (the rake tasks' stdout and
  # stderr); a missing input raises Error.
  class DirectusImport
    class Error < StandardError; end

    DEFAULT_DEST = "storage/imports/directus"

    attr_reader :db_path, :dest_dir

    def initialize(db_path, dest_dir = nil, out: $stdout, err: $stderr)
      raise Error, "Set db_path or DIRECTUS_DB" if db_path.blank?

      @db_path = db_path.to_s
      @dest_dir = (dest_dir.presence || DEFAULT_DEST).to_s
      @out = out
      @err = err
    end

    def all
      manifest_path = File.join(dest_dir, "directus-manifest.json")
      unless File.exist?(manifest_path)
        @out.puts "No manifest at #{manifest_path} — running scan first."
        scan
      end

      files
      collections
      block_types
      globals
      pages
    end

    # Schema only; writes nothing to the site.
    def scan
      require_db!
      FileUtils.mkdir_p(dest_dir)

      scan = ::Directus::SchemaScanner.new(db_path).call

      # The mapper accepts an empty list and emits target_exists=false for
      # every section; block-type intelligence isn't load-bearing here.
      existing_block_types =
        if defined?(BlockType) && BlockType.respond_to?(:all)
          BlockType.all.map { |bt| {slug: bt.slug, label: bt.label, fields: bt.fields} }
        else
          []
        end

      manifest = ::Directus::Mapper.new(scan, existing_block_types: existing_block_types).call
      manifest[:scan] = scan

      out_path = File.join(dest_dir, "directus-manifest.json")
      File.write(out_path, JSON.pretty_generate(manifest))

      @out.puts "Scanned: #{scan[:collections].size} collections, " \
                "#{scan[:files][:count] || 0} files, " \
                "#{scan[:users][:count] || 0} users"
      @out.puts "Wrote #{out_path}"
    end

    # A sidecar of every directus_files row. The SQLite export carries no
    # binaries, so this is informational: asset references are left blank and
    # reattached in the file manager afterwards.
    def files
      require_db!
      FileUtils.mkdir_p(dest_dir)

      db = SQLite3::Database.new(db_path, readonly: true)
      db.results_as_hash = true

      out = {}
      cols_present = db.execute("PRAGMA table_info(directus_files)").map { |r| r["name"] }
      if cols_present.empty?
        @out.puts "No directus_files table — skipping."
      else
        wanted = %w[id filename_disk filename_download title type filesize width height focal_point_x focal_point_y description folder].select { |c| cols_present.include?(c) }
        rows = db.execute("SELECT #{wanted.map { |c| %("#{c}") }.join(", ")} FROM directus_files")
        rows.each do |row|
          id = row["id"]
          next if id.nil? || id.empty?

          out[id] = row.reject { |k, _| k.is_a?(Integer) }
        end
      end

      out_path = File.join(dest_dir, "directus-files-manifest.json")
      File.write(out_path, JSON.pretty_generate(out))
      @out.puts "Wrote #{out_path} (#{out.size} file records, no binaries)"
    ensure
      db&.close
    end

    # Collections + entries for every "collection" role. Two passes so
    # cross-collection refs resolve; fills the slug map later stages read.
    def collections
      manifest = load_manifest!
      writer = ::Directus::Writer.new(manifest: manifest, files_manifest: load_files_manifest, slug_map: ::Directus::Writer.load_slug_map(dest_dir))
      collections = manifest["collections"].select { |c| c["role"] == "collection" }

      Collection.reset_column_information
      CollectionEntry.reset_column_information

      writer.with_db(db_path) do |db|
        @out.puts "Pass A: creating #{collections.size} Collections + entries (scalars)"
        collections.each { |c| write_collection(writer, db, c) }

        # Persist the slug map between passes so a re-run of a stage reads it.
        ::Directus::Writer.save_slug_map(dest_dir, writer.slug_map)

        @out.puts "Pass B: resolving record_refs across collections"
        collections.each { |c| resolve_collection_refs(writer, db, c) }
      end

      ::Directus::Writer.save_slug_map(dest_dir, writer.slug_map)
      @out.puts "Slug map written: #{File.join(dest_dir, ::Directus::Writer::SLUG_MAP_FILENAME)}"
    end

    # One BlockType per "section" collection. No data: sections are inlined
    # into page blocks at the pages stage.
    def block_types
      manifest = load_manifest!
      writer = ::Directus::Writer.new(manifest: manifest, slug_map: ::Directus::Writer.load_slug_map(dest_dir))
      sections = manifest["collections"].select { |c| c["role"] == "section" }

      BlockType.reset_column_information

      @out.puts "Writing #{sections.size} BlockTypes"
      created = updated = errored = 0

      sections.each do |c|
        mapping = c["mapping"] || {}
        # Section slugs use the BlockType format (underscores, leading letter).
        slug = writer.sanitize_identifier(mapping["target_block_type"] || c["directus_slug"])

        block_type = BlockType.find_or_initialize_by(slug: slug)
        existed = block_type.persisted?
        block_type.label = writer.humanize(c["directus_slug"])
        block_type.fields = (mapping["translated_fields"] || []).map { |f| writer.schema_field(f) }
        begin
          block_type.save!
          existed ? (updated += 1) : (created += 1)
        rescue ActiveRecord::RecordInvalid => e
          errored += 1
          @err.puts "  ✗ block_type #{slug}: #{e.message}"
        end
      end
      @out.puts "Done: #{created} created, #{updated} updated, #{errored} errored"
    end

    # Singletons: schema plus the one row of data, refs resolved.
    def globals
      manifest = load_manifest!
      writer = ::Directus::Writer.new(manifest: manifest, files_manifest: load_files_manifest, slug_map: ::Directus::Writer.load_slug_map(dest_dir))
      globals = manifest["collections"].select { |c| c["role"] == "global" }

      Global.reset_column_information

      writer.with_db(db_path) do |db|
        @out.puts "Writing #{globals.size} Globals"
        created = updated = errored = 0

        globals.each do |c|
          directus_name = c["directus_slug"]
          mapping = c["mapping"] || {}
          slug = writer.sanitize_identifier(mapping["global_slug"] || directus_name)
          mappings = mapping["schema_fields"] || []

          global = Global.find_or_initialize_by(slug: slug)
          existed = global.persisted?
          global.name = mapping["global_name"] || writer.humanize(directus_name)
          global.schema = {"fields" => mappings.map { |f| writer.schema_field(f) }}

          data =
            if writer.table_exists?(db, directus_name)
              row = db.execute("SELECT * FROM #{quote(directus_name)} LIMIT 1").first
              row ? writer.translate_row(db, row.reject { |k, _| k.is_a?(Integer) }, mappings) : {}
            else
              {}
            end
          global.data = global.new_record? || global.data.blank? ? data : global.data.merge(data)

          begin
            global.save!
            existed ? (updated += 1) : (created += 1)
          rescue ActiveRecord::RecordInvalid => e
            errored += 1
            @err.puts "  ✗ global #{slug}: #{e.message}"
          end
        end
        @out.puts "Done: #{created} created, #{updated} updated, #{errored} errored"
      end
    end

    # Pages, walking the M2A junction: each junction row becomes one block
    # (type = the section's block type, data = its translated row).
    def pages
      manifest = load_manifest!
      page_meta = manifest["collections"].find { |c| c["role"] == "page" }
      unless page_meta
        @out.puts "No `page` role in manifest — skipping pages stage."
        return
      end

      page_collection = manifest["page_collection"] || page_meta["directus_slug"]
      writer = ::Directus::Writer.new(manifest: manifest, files_manifest: load_files_manifest, slug_map: ::Directus::Writer.load_slug_map(dest_dir))

      Page.reset_column_information

      writer.with_db(db_path) do |db|
        mapping = page_meta["mapping"] || {}
        blocks_field = mapping["blocks_source"]
        frontmatter = mapping["frontmatter"] || []
        section_index = section_index_for(manifest, writer)

        rows = db.execute("SELECT * FROM #{quote(page_collection)}")
        created = updated = errored = 0
        @out.puts "Writing #{rows.size} pages"

        rows.each do |row|
          clean = row.reject { |k, _| k.is_a?(Integer) }
          title = clean[mapping["title_source"]].to_s
          next if title.empty? && clean[mapping["slug_source"]].to_s.empty?

          slug = writer.sanitize_slug(clean[mapping["slug_source"]].to_s.empty? ? title : clean[mapping["slug_source"]])
          slug = writer.sanitize_slug("page-#{clean["id"].to_s[0, 8]}") if slug.empty?

          blocks = blocks_field ? build_blocks(writer, db, page_collection, blocks_field, clean["id"], section_index) : []

          seo_hash, seo_consumed = writer.extract_seo(clean, frontmatter)
          non_seo_frontmatter = frontmatter.reject { |f| seo_consumed.include?((f["cms_name"] || f[:cms_name]).to_s) }

          page = Page.find_or_initialize_by(slug: slug)
          existed = page.persisted?
          page.assign_attributes(
            title:        title.presence || writer.humanize(slug),
            status:       status_for(clean[mapping["status_source"]]),
            locale:       "en",
            tags:         [],
            blocks:       blocks,
            seo:          seo_hash,
            frontmatter:  writer.translate_row(db, clean, non_seo_frontmatter),
            published_at: parse_time(clean["date_created"])
          )

          begin
            page.save!
            existed ? (updated += 1) : (created += 1)
          rescue ActiveRecord::RecordInvalid => e
            errored += 1
            @err.puts "  ✗ page #{slug}: #{e.message}"
          end
        end
        @out.puts "Done: #{created} created, #{updated} updated, #{errored} errored"
      end
    end

    private

    def require_db!
      raise Error, "DB not found: #{db_path}" unless File.exist?(db_path)
    end

    def load_manifest!
      path = File.join(dest_dir, "directus-manifest.json")
      raise Error, "No manifest at #{path} — run import:directus:scan first" unless File.exist?(path)

      JSON.parse(File.read(path))
    end

    def load_files_manifest
      path = File.join(dest_dir, "directus-files-manifest.json")
      File.exist?(path) ? JSON.parse(File.read(path)) : {}
    end

    # Pass A for one collection: its schema, then its rows' scalar fields.
    def write_collection(writer, db, c)
      directus_name = c["directus_slug"]
      mapping = c["mapping"] || {}
      cms_slug = mapping["cms_collection_slug"] || writer.sanitize_slug(directus_name)
      mappings = mapping["schema_fields"] || []

      collection = Collection.find_or_initialize_by(slug: cms_slug)
      collection.name = mapping["cms_collection_name"] || writer.humanize(directus_name)
      # SEO-shaped fields go on entry.seo (its own panel), so they stay out of
      # the schema too.
      collection.schema = {"fields" => mappings.reject { |f| writer.seo_field?(f) }.map { |f| writer.schema_field(f) }}
      collection.save!

      unless writer.table_exists?(db, directus_name)
        @err.puts "  ! source table missing: #{directus_name} — schema only"
        return
      end

      rows = db.execute("SELECT * FROM #{quote(directus_name)}")
      created = updated = errored = 0
      rows.each do |row|
        clean_row = row.reject { |k, _| k.is_a?(Integer) }
        title = title_for(writer, clean_row, mappings, mapping)
        slug = slug_for(writer, clean_row, mappings, mapping, title)
        writer.record_slug(directus_name, clean_row["id"], slug)

        seo_hash, seo_consumed = writer.extract_seo(clean_row, mappings)
        non_seo = mappings.reject { |f| seo_consumed.include?((f["cms_name"] || f[:cms_name]).to_s) }

        entry = collection.entries.find_or_initialize_by(slug: slug)
        existed = entry.persisted?
        entry.assign_attributes(
          title:         title,
          status:        status_for(clean_row[mapping["status_source"]]),
          locale:        "en",
          seo:           seo_hash,
          frontmatter:   writer.translate_row(db, clean_row, non_seo, skip_refs: true),
          body_markdown: body_for(clean_row, mapping["body_source"]),
          published_at:  parse_time(clean_row["date_created"])
        )
        begin
          entry.save!
          existed ? (updated += 1) : (created += 1)
        rescue ActiveRecord::RecordInvalid => e
          errored += 1
          @err.puts "  ✗ #{cms_slug}/#{slug}: #{e.message}"
        end
      end
      @out.puts "  ✓ #{cms_slug}: #{created} created, #{updated} updated, #{errored} errored (#{rows.size} rows)"
    end

    # Pass B for one collection: record_refs values, now the slug map is full.
    def resolve_collection_refs(writer, db, c)
      directus_name = c["directus_slug"]
      mapping = c["mapping"] || {}
      cms_slug = mapping["cms_collection_slug"] || writer.sanitize_slug(directus_name)
      mappings = mapping["schema_fields"] || []
      return unless mappings.any? { |f| %w[m2m o2m].include?(f["directus_type"].to_s) }
      return unless writer.table_exists?(db, directus_name)

      collection = Collection.find_by(slug: cms_slug)
      return unless collection

      updated = 0
      db.execute("SELECT * FROM #{quote(directus_name)}").each do |row|
        clean_row = row.reject { |k, _| k.is_a?(Integer) }
        row_slug = writer.slug_map.dig(directus_name, clean_row["id"])
        next unless row_slug

        entry = collection.entries.find_by(slug: row_slug)
        next unless entry

        refs = writer.translate_row(db, clean_row, mappings, only_refs: true)
        next if refs.empty?

        entry.frontmatter = (entry.frontmatter || {}).merge(refs)
        begin
          entry.save!
          updated += 1
        rescue ActiveRecord::RecordInvalid => e
          @err.puts "  ✗ refs #{cms_slug}/#{row_slug}: #{e.message}"
        end
      end
      @out.puts "  ↻ #{cms_slug}: refs updated on #{updated} entries" if updated > 0
    end

    # section collection name → {bt_slug, mappings, bt_fields}
    def section_index_for(manifest, writer)
      manifest["collections"].select { |c| c["role"] == "section" }.each_with_object({}) do |c, index|
        slug = writer.sanitize_identifier(c.dig("mapping", "target_block_type") || c["directus_slug"])
        index[c["directus_slug"]] = {bt_slug: slug, mappings: c.dig("mapping", "translated_fields") || [],
                                     bt_fields: BlockType.find_by(slug: slug)&.fields || []}
      end
    end

    # A page's blocks, from its M2A junction rows in `sort` order.
    def build_blocks(writer, db, page_collection, blocks_field, page_id, section_index)
      writer.walk_m2a_for_page(db, page_collection, blocks_field, page_id).filter_map do |junction_row|
        section_name = junction_row["collection"]
        item_id = junction_row["item"]
        index = section_index[section_name]
        unless index
          @err.puts "  ! page=#{page_id}: unknown section '#{section_name}' — skipping block"
          next
        end
        next unless writer.table_exists?(db, section_name)

        section_row = db.execute("SELECT * FROM #{quote(section_name)} WHERE id = ? LIMIT 1", [item_id]).first
        unless section_row
          @err.puts "  ! page=#{page_id}: missing #{section_name} row #{item_id}"
          next
        end
        data = writer.translate_row(db, section_row.reject { |k, _| k.is_a?(Integer) }, index[:mappings])
        data = BlockType.coerce_data(index[:bt_fields], data) if index[:bt_fields].present?

        {"type" => index[:bt_slug], "version" => 1, "data" => data}
      end
    end

    def quote(ident)
      %("#{ident.to_s.gsub('"', '""')}")
    end

    # Directus uses the CMS's own published/draft/archived; anything else is a draft.
    def status_for(status)
      %w[published draft archived].include?(status.to_s) ? status : "draft"
    end

    def parse_time(value)
      return nil if value.nil? || value.to_s.empty?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def body_for(row, body_source)
      return "" if body_source.nil? || body_source.empty?

      row[body_source].to_s
    end

    # The mapping's title source when the row has one, else the writer's
    # synthesis (first text field, or "Untitled").
    def title_for(writer, row, mappings, mapping)
      source = mapping["title_source"]
      return writer.truncate(row[source].to_s.strip, 200) if source && row[source].to_s.strip != ""

      writer.synthesize_title(row, mappings)
    end

    def slug_for(writer, row, mappings, mapping, title)
      source = mapping["slug_source"]
      if source && row[source].to_s.strip != ""
        slug = writer.sanitize_slug(row[source].to_s)
        return slug unless slug.empty?
      end
      writer.synthesize_slug(row, title)
    end
  end
end
