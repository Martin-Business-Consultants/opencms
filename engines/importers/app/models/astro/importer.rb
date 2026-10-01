# frozen_string_literal: true

require "set"

module Astro
  # Walks an extracted Astro repo and creates CMS records for it. Three
  # passes:
  #
  #   1. Assets   — every file under `assets_path` becomes an Asset, indexed
  #                 by its absolute filesystem path so markdown references
  #                 can be rewritten to point at the new blob URL.
  #   2. Content  — every subdirectory of `content_path` becomes a Collection.
  #                 Markdown files become CollectionEntries with frontmatter
  #                 preserved verbatim.
  #   3. Pages    — every markdown/MDX file under `pages_path` becomes a Page.
  #
  # MDX files are skipped (their JSX components don't render anywhere
  # downstream); the count is reported in the result.
  #
  # Idempotent: re-running upserts by slug at every level.
  class Importer
    Result = Struct.new(
      :assets_created, :assets_skipped,
      :collections_created, :collections_existed,
      :entries_created, :entries_updated, :entries_errored,
      :pages_created, :pages_updated, :pages_errored,
      :mdx_skipped, :messages,
      keyword_init: true
    )

    MARKDOWN_EXT = %w[.md .markdown].freeze
    MDX_EXT      = %w[.mdx].freeze
    IMAGE_EXT    = %w[.png .jpg .jpeg .gif .webp .avif .svg .heic].freeze

    def initialize(repo_root:, content_path: "src/content", pages_path: "src/pages",
      assets_path: "src/assets", rewrite_images: true)
      @repo_root      = repo_root
      @content_path   = content_path
      @pages_path     = pages_path
      @assets_path    = assets_path
      @rewrite_images = rewrite_images
      @asset_map      = {}
      @result         = empty_result
    end

    def import
      import_assets if @assets_path.present?
      import_content if @content_path.present?
      import_pages if @pages_path.present?
      @result
    end

    private

    def empty_result
      Result.new(
        assets_created: 0, assets_skipped: 0,
        collections_created: 0, collections_existed: 0,
        entries_created: 0, entries_updated: 0, entries_errored: 0,
        pages_created: 0, pages_updated: 0, pages_errored: 0,
        mdx_skipped: 0, messages: []
      )
    end

    # ---------- Assets ----------

    def import_assets
      root = File.join(@repo_root, @assets_path)
      return note("assets path not found: #{@assets_path}") unless File.directory?(root)

      Dir.glob(File.join(root, "**/*")).each do |path|
        next unless File.file?(path)
        next unless IMAGE_EXT.include?(File.extname(path).downcase)

        asset = upsert_asset(path)
        if asset
          @asset_map[File.expand_path(path)] = asset
          @result.assets_created += 1
        else
          @result.assets_skipped += 1
        end
      end
    end

    def upsert_asset(path)
      relative = path.sub("#{@repo_root}/", "")
      folder   = "/astro-import/" + File.dirname(relative).split("/").reject(&:empty?).join("/")
      folder   = folder.chomp("/")

      base = File.basename(path, ".*")
      asset = Asset.new(name: base.presence || "(image)", folder: folder)
      File.open(path, "rb") do |io|
        asset.file.attach(io: io, filename: File.basename(path))
        asset.save!
      end
      asset
    rescue StandardError => e
      Rails.logger.warn("[astro import] asset failed #{path}: #{e.class}: #{e.message}")
      nil
    end

    # ---------- Content collections ----------

    def import_content
      root = File.join(@repo_root, @content_path)
      return note("content path not found: #{@content_path}") unless File.directory?(root)

      Dir.children(root).each do |dirname|
        full = File.join(root, dirname)
        next unless File.directory?(full)
        next if dirname.start_with?(".")

        collection = upsert_collection(dirname)
        next unless collection

        files = Dir.glob(File.join(full, "**/*"))
                  .select { |p| File.file?(p) }
        files.each do |path|
          ext = File.extname(path).downcase
          if MDX_EXT.include?(ext)
            @result.mdx_skipped += 1
            next
          end
          next unless MARKDOWN_EXT.include?(ext)

          import_entry(collection, path, full)
        end
      end
    end

    def upsert_collection(slug)
      slug = slug.parameterize
      coll = Collection.find_or_initialize_by(slug: slug)
      existed = coll.persisted?
      coll.name   = slug.humanize if coll.name.blank?
      coll.schema ||= {"fields" => []}
      coll.save!

      if existed
        @result.collections_existed += 1
      else
        @result.collections_created += 1
      end
      coll
    rescue StandardError => e
      note("collection #{slug.inspect} failed: #{e.class}: #{e.message}")
      nil
    end

    def import_entry(collection, path, collection_root)
      content = File.read(path)
      parsed  = Markdown.parse(content)
      slug    = derive_slug(parsed[:frontmatter], path, collection_root)
      title   = parsed[:frontmatter]["title"].presence || slug.humanize
      status  = parsed[:frontmatter]["draft"] ? "draft" : "published"

      body = parsed[:body]
      body = Markdown.rewrite_images(body, source_file: path, asset_map: @asset_map) if @rewrite_images

      entry = collection.entries.find_or_initialize_by(slug: slug)
      existed = entry.persisted?
      entry.assign_attributes(
        title:         title,
        status:        status,
        locale:        parsed[:frontmatter]["locale"].presence || "en",
        frontmatter:   sanitize_frontmatter(parsed[:frontmatter]),
        body_markdown: body,
        published_at:  status == "published" ? Time.current : nil
      )
      entry.save!
      existed ? @result.entries_updated += 1 : @result.entries_created += 1
    rescue StandardError => e
      @result.entries_errored += 1
      note("entry #{File.basename(path)} failed: #{e.class}: #{e.message}")
    end

    # ---------- Pages ----------

    def import_pages
      root = File.join(@repo_root, @pages_path)
      return note("pages path not found: #{@pages_path}") unless File.directory?(root)

      Dir.glob(File.join(root, "**/*")).each do |path|
        next unless File.file?(path)
        ext = File.extname(path).downcase
        if MDX_EXT.include?(ext)
          @result.mdx_skipped += 1
          next
        end
        next unless MARKDOWN_EXT.include?(ext)

        import_page(path, root)
      end
    end

    def import_page(path, pages_root)
      content = File.read(path)
      parsed  = Markdown.parse(content)
      slug    = derive_slug(parsed[:frontmatter], path, pages_root)
      title   = parsed[:frontmatter]["title"].presence || slug.humanize
      status  = parsed[:frontmatter]["draft"] ? "draft" : "published"

      body = parsed[:body]
      body = Markdown.rewrite_images(body, source_file: path, asset_map: @asset_map) if @rewrite_images

      blocks = body.strip.empty? ? [] : [{
        "type" => "text", "version" => 1, "data" => {"body" => body}
      }]

      page = Page.find_or_initialize_by(slug: slug)
      existed = page.persisted?
      page.assign_attributes(
        title:        title,
        status:       status,
        locale:       parsed[:frontmatter]["locale"].presence || "en",
        blocks:       blocks,
        frontmatter:  sanitize_frontmatter(parsed[:frontmatter]),
        seo:          parsed[:frontmatter]["seo"].is_a?(Hash) ? parsed[:frontmatter]["seo"] : {},
        published_at: status == "published" ? Time.current : nil
      )
      page.save!
      existed ? @result.pages_updated += 1 : @result.pages_created += 1
    rescue StandardError => e
      @result.pages_errored += 1
      note("page #{File.basename(path)} failed: #{e.class}: #{e.message}")
    end

    # ---------- Helpers ----------

    def derive_slug(frontmatter, path, root_dir)
      explicit = frontmatter["slug"].to_s.strip
      return explicit.parameterize if explicit.present?

      relative = path.sub("#{root_dir}/", "")
      base     = relative.sub(/\.[^.]+\z/, "")
      base = base.sub(/\/index\z/, "") # `foo/index.md` → `foo`

      base.split("/").map { |seg| seg.parameterize }.reject(&:empty?).last || "untitled"
    end

    # Drop keys that we map to top-level columns so they don't double up
    # in `frontmatter`. Everything else passes through verbatim.
    def sanitize_frontmatter(fm)
      return {} unless fm.is_a?(Hash)

      fm.reject { |k, _| %w[title slug status draft locale tags seo].include?(k.to_s) }
    end

    def note(msg)
      Rails.logger.info("[astro import] #{msg}")
      @result.messages << msg
    end
  end
end
