# frozen_string_literal: true

require "cgi"
require "fileutils"
require "json"
require "nokogiri"
require "open-uri"
require "uri"

module Importers
  # One WordPress WXR export into this site, in stages, media first so the
  # binaries are ours before the source site goes away:
  #
  #   import = Importers::WordpressImport.new(xml_path, dest_dir)
  #   import.media   # mirror attachments into dest_dir/uploads + media-manifest.json
  #   import.assets  # an Asset per mirrored file (asset ids back into the manifest)
  #   import.site    # the export's site title and tagline into Settings › General, if unset
  #   import.posts   # 'post' items → a Posts collection, with category and tag pools
  #   import.pages   # 'page' items → Pages, parents wired from wp:post_parent
  #   import.all     # every stage in that order
  #
  # Each content stage is self-contained: it creates the category and tag pool
  # collections it needs, fills them from the WP taxonomy terms its post type
  # uses, then writes the content with its relations (category, tags). A site
  # with custom post types subclasses this with its own stages, as
  # Importers::OldMillImport does for beer, food and specials.
  #
  # Progress goes to `out` and problems to `err` (the rake tasks' stdout and
  # stderr); a missing input raises Error.
  class WordpressImport
    class Error < StandardError; end

    DEFAULT_XML = "tmp/wordpress.xml"
    DEFAULT_DEST = "storage/imports/wordpress"
    MODES = %w[upsert create].freeze

    attr_reader :xml_path, :dest_dir, :mode

    # mode: "upsert" lets WordPress overwrite existing beers; "create" only
    # writes beers whose slug isn't in the collection yet, so a re-import
    # can't revert edits made in the CMS since.
    def initialize(xml_path = nil, dest_dir = nil, mode: nil, out: $stdout, err: $stderr)
      @xml_path = (xml_path.presence || self.class::DEFAULT_XML).to_s
      @dest_dir = (dest_dir.presence || self.class::DEFAULT_DEST).to_s
      @mode = (mode.presence || "upsert").to_s
      raise Error, "mode must be 'upsert' or 'create', got #{@mode.inspect}" unless MODES.include?(@mode)

      @out = out
      @err = err
    end

    def all
      media
      assets
      site
      posts
      pages
    end

    def media
      raise Error, "XML not found: #{xml_path}" unless File.exist?(xml_path)

      attachments = items_of_type("attachment")

      uploads_dir = File.join(dest_dir, "uploads")
      FileUtils.mkdir_p(uploads_dir)

      manifest = {}
      ok = skipped = errored = 0

      @out.puts "Mirroring #{attachments.size} attachments → #{uploads_dir}"

      attachments.each_with_index do |item, i|
        post_id = item.at_xpath("./post_id")&.text&.to_i
        url = item.at_xpath("./attachment_url")&.text&.strip
        next if url.nil? || url.empty?

        rel_path = postmeta(item, "_wp_attached_file") || URI.parse(url).path.sub(%r{^.*/wp-content/uploads/}, "")
        local_path = File.join(uploads_dir, rel_path)

        status =
          if File.exist?(local_path) && File.size(local_path).positive?
            skipped += 1
            "cached"
          else
            FileUtils.mkdir_p(File.dirname(local_path))
            begin
              URI.parse(url).open(read_timeout: 30, open_timeout: 10) do |io|
                File.binwrite(local_path, io.read)
              end
              ok += 1
              "ok"
            rescue => e
              File.delete(local_path) if File.exist?(local_path)
              errored += 1
              @err.puts "  ✗ #{url} → #{e.class}: #{e.message}"
              "error: #{e.class}: #{e.message}"
            end
          end

        manifest[post_id] = {
          wp_post_id: post_id,
          url: url,
          path: rel_path,
          title: item.at_xpath("./title")&.text,
          alt: postmeta(item, "_wp_attachment_image_alt"),
          status: status,
          bytes: File.exist?(local_path) ? File.size(local_path) : 0
        }

        @out.printf "\r  [%d/%d] %d ok · %d cached · %d errored", i + 1, attachments.size, ok, skipped, errored
      end
      @out.puts ""

      path = manifest_path
      File.write(path, JSON.pretty_generate(manifest))
      @out.puts "Wrote #{path} (#{manifest.size} entries)"
    end

    def assets
      path = manifest_path
      raise Error, "Run import:wordpress:media first (no manifest at #{path})" unless File.exist?(path)

      manifest = JSON.parse(File.read(path))
      uploads_dir = File.join(dest_dir, "uploads")

      Asset.reset_column_information
      created = existing = errored = 0

      @out.puts "Importing #{manifest.size} assets"

      manifest.each_with_index do |(_post_id, entry), i|
        next if entry["status"] != "ok"

        local_path = File.join(uploads_dir, entry["path"])
        unless File.exist?(local_path)
          @err.puts "  ✗ missing file: #{local_path}"
          errored += 1
          next
        end

        if entry["asset_id"] && Asset.exists?(id: entry["asset_id"])
          existing += 1
        else
          sub = File.dirname(entry["path"])
          begin
            asset = Asset.new(
              name:   entry["title"].presence || File.basename(entry["path"], ".*"),
              folder: sub == "." ? "/oldmill" : "/oldmill/#{sub}"
            )
            File.open(local_path, "rb") do |io|
              asset.file.attach(io: io, filename: File.basename(entry["path"]))
              asset.save!
            end
            entry["asset_id"] = asset.id
            created += 1
          rescue => e
            errored += 1
            @err.puts "  ✗ #{entry["path"]} → #{e.class}: #{e.message}"
          end
        end

        @out.printf "\r  [%d/%d] %d created · %d existed · %d errored", i + 1, manifest.size, created, existing, errored
      end
      @out.puts ""

      File.write(path, JSON.pretty_generate(manifest))
      @out.puts "Updated manifest with asset_id mappings"
    end

    # The site's title and tagline, from the export's channel, into
    # Settings › General — only where the site hasn't set its own.
    def site
      channel = document.at_xpath("//channel")
      general = Setting.get("general")
      incoming = {
        "title" => wp_text(channel&.at_xpath("./title")).presence,
        "description" => wp_text(channel&.at_xpath("./description")).presence
      }.compact.reject { |key, _| general[key].present? }

      Setting.set("general", incoming) if incoming.any?
      @out.puts(incoming.any? ? "Set the site's #{incoming.keys.join(" and ")} from the export" : "Site title and description already set; left alone")
    end

    # WordPress's blog: 'post' items into a Posts collection, with its
    # categories and tags as the collection's pools, the featured image and
    # SEO carried over, and the author's name noted in the frontmatter (users
    # aren't imported).
    def posts
      create_only = mode == "create"
      manifest = load_manifest
      posts = items_of_type("post")

      Collection.reset_column_information
      CollectionEntry.reset_column_information

      category_titles = term_titles(posts, "category")
      tag_titles = term_titles(posts, "post_tag")
      categories_pool = upsert_pool!(slug: "post-categories", name: "Post categories")
      tags_pool = upsert_pool!(slug: "post-tags", name: "Post tags")
      category_entries = upsert_pool_entries!(categories_pool, category_titles)
      tag_entries = upsert_pool_entries!(tags_pool, tag_titles)

      collection = Collection.find_or_initialize_by(slug: "posts")
      collection.name ||= "Posts"
      collection.schema = {"fields" => merge_fields(collection.fields, [
        {"name" => "featured_image", "label" => "Featured image", "type" => "asset"},
        {"name" => "author", "label" => "Author", "type" => "string", "help" => "The WordPress author, by name."},
        {"name" => "excerpt", "label" => "Excerpt", "type" => "text"}
      ])}
      collection.categories_collection = categories_pool
      collection.tags_collection = tags_pool
      collection.save!

      authors = document.xpath("//channel/author").to_h do |author|
        [author.at_xpath("./author_login")&.text.to_s, wp_text(author.at_xpath("./author_display_name")).presence]
      end

      @out.puts "Collection posts (id=#{collection.id}) ready — #{category_titles.size} categories, #{tag_titles.size} tags, #{posts.size} posts"
      created = updated = skipped = errored = 0

      posts.each_with_index do |item, i|
        slug = wp_text(item.at_xpath("./post_name")).presence
        title = wp_text(item.at_xpath("./title")).presence
        next unless slug && title

        if create_only && collection.entries.exists?(slug: slug)
          skipped += 1
          next
        end

        status = wp_status_to_local(item.at_xpath("./status")&.text)
        login = item.at_xpath("./creator")&.text.to_s
        frontmatter = {}
        frontmatter["featured_image"] = featured_image_id(item, manifest).to_s if featured_image_id(item, manifest)
        frontmatter["author"] = authors[login] || login if login.present?
        excerpt = wp_text(item.at_xpath("./excerpt_encoded") || item.xpath("./encoded")[1]).presence
        frontmatter["excerpt"] = strip_tags(excerpt).strip if excerpt

        entry = collection.entries.find_or_initialize_by(slug: slug)
        existed = entry.persisted?
        entry.assign_attributes(
          title: title,
          status: status,
          frontmatter: frontmatter,
          body_markdown: gutenberg_to_markdown(item.at_xpath("./encoded")&.text.to_s),
          published_at: parse_published_at(item, status),
          category: term_slugs(item, "category").first&.then { category_entries[it] },
          tags: term_slugs(item, "post_tag").filter_map { tag_entries[it] },
          seo: extract_seo(item, manifest: manifest)
        )

        begin
          entry.save!
          existed ? (updated += 1) : (created += 1)
        rescue ActiveRecord::RecordInvalid => e
          errored += 1
          @err.puts "  ✗ posts/#{slug}: #{e.message}"
        end

        @out.printf "\r  [%d/%d] %d created · %d updated · %d skipped · %d errored", i + 1, posts.size, created, updated, skipped, errored
      end
      @out.puts ""
      @out.puts "Done: #{created} created, #{updated} updated, #{skipped} skipped, #{errored} errored"
    end

    def pages
      manifest = load_manifest
      pages = items_of_type("page")

      Page.reset_column_information
      Collection.reset_column_information

      # The two convention-named pools pages share, created empty: the WP
      # export carries no page-level taxonomies.
      upsert_pool!(slug: Page::PAGE_CATEGORIES_SLUG, name: "Page categories")
      upsert_pool!(slug: Page::PAGE_TAGS_SLUG, name: "Page tags")

      @out.puts "Importing #{pages.size} pages"

      created = updated = errored = 0
      # post_id → page, for wiring wp:post_parent once every page exists.
      pages_by_wp_id = {}

      pages.each_with_index do |item, i|
        slug = wp_text(item.at_xpath("./post_name")).presence
        title = wp_text(item.at_xpath("./title")).presence
        next unless slug && title

        status = wp_status_to_local(item.at_xpath("./status")&.text)
        blocks = gutenberg_to_blocks(item.at_xpath("./encoded")&.text.to_s, manifest: manifest)

        # An essentially empty page whose slug is a collection's becomes that
        # collection's index.
        if blocks.empty? && (matched = Collection.find_by(slug: slug))
          blocks << collection_index_block(matched)
        end

        page = Page.find_or_initialize_by(slug: slug)
        existed = page.persisted?
        page.assign_attributes(
          title:        title,
          status:       status,
          blocks:       blocks,
          frontmatter:  {},
          published_at: parse_published_at(item, status),
          seo:          extract_seo(item, manifest: manifest)
        )

        begin
          page.save!
          wp_post_id = item.at_xpath("./post_id")&.text&.to_i
          pages_by_wp_id[wp_post_id] = page if wp_post_id
          existed ? (updated += 1) : (created += 1)
        rescue ActiveRecord::RecordInvalid => e
          errored += 1
          @err.puts "  ✗ pages/#{slug}: #{e.message}"
        end

        @out.printf "\r  [%d/%d] %d created · %d updated · %d errored", i + 1, pages.size, created, updated, errored
      end
      @out.puts ""

      # A second pass, so a child exported before its parent still links.
      relinked = 0
      pages.each do |item|
        parent_wp_id = item.at_xpath("./post_parent")&.text&.to_i
        next unless parent_wp_id && parent_wp_id.positive?

        child = pages_by_wp_id[item.at_xpath("./post_id")&.text&.to_i]
        parent = pages_by_wp_id[parent_wp_id]
        next unless child && parent && child.parent_id != parent.id

        child.update!(parent_id: parent.id)
        relinked += 1
      end
      @out.puts "Linked #{relinked} pages to a parent (via wp:post_parent)" if relinked.positive?
      @out.puts "Done: #{created} created, #{updated} updated, #{errored} errored"
    end

    private

    def manifest_path
      File.join(dest_dir, "media-manifest.json")
    end

    def load_manifest
      File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path)) : {}
    end

    def document
      @document ||= Nokogiri::XML(File.read(xml_path)).tap(&:remove_namespaces!)
    end

    def items_of_type(post_type)
      document.xpath("//item").select { |item| item.at_xpath("./post_type")&.text == post_type }
    end

    # {nicename => title} for the terms of one taxonomy used by these items.
    def term_titles(items, domain)
      items.each_with_object({}) do |item, titles|
        item.xpath("./category[@domain='#{domain}']").each do |term|
          slug = term["nicename"].to_s
          next if slug.empty?

          titles[slug] ||= wp_text(term).presence || slug.tr("-", " ").capitalize
        end
      end
    end

    def term_slugs(item, domain)
      item.xpath("./category[@domain='#{domain}']").map { |term| term["nicename"].to_s }.reject(&:empty?).uniq
    end

    def featured_image_id(item, manifest)
      thumb = postmeta(item, "_thumbnail_id")
      thumb && manifest[thumb]&.dig("asset_id")
    end

    # Schema fields the import needs, folded into what the collection already
    # declares: existing fields keep their position and edits, missing ones
    # are appended.
    def merge_fields(existing, required)
      have = Array(existing).select { |f| f.is_a?(Hash) && f["name"].present? }
      names = have.map { |f| f["name"] }
      have + required.reject { |f| names.include?(f["name"]) }
    end

    def wp_status_to_local(status)
      case status
      when "publish", "future" then "published"
      when "trash"             then "archived"
      else "draft"
      end
    end

    def parse_published_at(item, status)
      return nil unless status == "published"

      Time.parse(item.at_xpath("./post_date_gmt")&.text) rescue nil
    end

    # WP wraps CDATA around already-escaped content ("&amp;" stays literal),
    # so decode after extraction.
    def wp_text(node)
      raw = node&.text.to_s
      raw.empty? ? raw : CGI.unescapeHTML(raw)
    end

    # A collection_list block tuned per known collection: food groups by
    # section, everything else is a flat grid.
    def collection_index_block(collection)
      data = {
        "collection_slug" => collection.slug,
        "heading"         => collection.name,
        "filter_status"   => "published",
        "sort_by"         => (collection.slug == "food") ? "title" : "published_at",
        "sort_dir"        => (collection.slug == "food") ? "asc" : "desc",
        "limit"           => 0,
        "layout"          => (collection.slug == "beers") ? "featured-first" : "grid"
      }
      data["group_by"] = "category" if collection.slug == "food"

      {"type" => "collection_list", "version" => 1, "data" => data}
    end

    # A pool (categories or tags) is an ordinary collection that another
    # collection points at from categories_collection_id / tags_collection_id.
    def upsert_pool!(slug:, name:)
      pool = Collection.find_or_initialize_by(slug: slug)
      pool.name = name if pool.new_record? || pool.name.blank?
      pool.schema = {"fields" => []} if pool.new_record? || !pool.schema.is_a?(Hash)
      pool.save!
      pool
    end

    def ensure_pool_field!(pool, name, type, **extra)
      fields = (pool.schema || {})["fields"] || []
      return if fields.any? { |f| f["name"] == name }

      pool.schema = pool.schema.merge("fields" => fields + [{"name" => name, "type" => type, **extra.stringify_keys}])
      pool.save!
    end

    # One entry per (slug, title) in the pool, idempotently; {slug => entry}.
    # Yields each entry for extra setup (a `position`).
    def upsert_pool_entries!(pool, titles_by_slug)
      titles_by_slug.each_with_object({}) do |(slug, title), entries|
        entry = pool.entries.find_or_initialize_by(slug: slug)
        entry.assign_attributes(title: title, status: "published", body_markdown: entry.body_markdown.presence || "")
        entry.frontmatter ||= {}
        yield(entry, slug) if block_given?
        entry.save!
        entries[slug] = entry
      end
    end

    def postmeta(item, key)
      item.xpath("./postmeta").find { |meta| meta.at_xpath("./meta_key")&.text == key }&.at_xpath("./meta_value")&.text
    end

    # Yoast's meta into the `seo` column, without its UI noise; a blank
    # description is left out so the site's default applies.
    def extract_seo(item, manifest:)
      seo = {}

      description = postmeta(item, "_yoast_wpseo_metadesc").to_s.strip
      seo["description"] = description if description.present?

      canonical = postmeta(item, "_yoast_wpseo_canonical").to_s.strip
      seo["canonical"] = canonical if canonical.present?

      seo["noindex"] = true if postmeta(item, "_yoast_wpseo_meta-robots-noindex") == "1"

      og_id = postmeta(item, "_yoast_wpseo_opengraph-image-id") || postmeta(item, "_yoast_wpseo_twitter-image-id")
      if og_id && (mapped = manifest[og_id.to_s]&.dig("asset_id"))
        seo["og_image"] = mapped.to_s
      end

      seo
    end

    # Pragmatic Gutenberg-to-markdown for the surface this export uses
    # (paragraphs, headings, lists, basic inline). Not a full converter.
    def gutenberg_to_markdown(html)
      return "" if html.nil? || html.empty?

      text = html.dup
      text.gsub!(/<!--\s*\/?wp:[^>]*-->/, "")

      text.gsub!(/<h([1-6])[^>]*>(.*?)<\/h\1>/m) { ("#" * $1.to_i) + " " + $2.strip + "\n\n" }
      text.gsub!(/<p[^>]*>(.*?)<\/p>/m) { $1.strip + "\n\n" }
      text.gsub!(/<li[^>]*>(.*?)<\/li>/m) { "- " + $1.strip + "\n" }
      text.gsub!(/<\/?ul[^>]*>/, "\n")
      text.gsub!(/<\/?ol[^>]*>/, "\n")
      text.gsub!(/<br\s*\/?>/i, "  \n")

      text.gsub!(/<strong[^>]*>(.*?)<\/strong>/m) { "**#{$1}**" }
      text.gsub!(/<b[^>]*>(.*?)<\/b>/m) { "**#{$1}**" }
      text.gsub!(/<em[^>]*>(.*?)<\/em>/m) { "*#{$1}*" }
      text.gsub!(/<i[^>]*>(.*?)<\/i>/m) { "*#{$1}*" }
      text.gsub!(/<a[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>/m) { "[#{$2}](#{$1})" }

      text.gsub!(/<[^>]+>/, "")

      text = CGI.unescapeHTML(text)
      text.gsub!(/[ \t]+\n/, "\n")
      text.gsub!(/\n{3,}/, "\n\n")
      text.strip
    end

    # A Gutenberg body as page blocks: walk the wp:* block comments in order,
    # split on H2s (each starts a `text` block headed "## …"), and pull
    # wp:image / wp:gallery out as their own blocks. Anything else falls
    # through to the markdown converter.
    def gutenberg_to_blocks(html, manifest:)
      return [] if html.nil? || html.strip.empty?

      sections = []
      current_md = +""
      flush_text = -> {
        md = current_md.strip
        sections << {"type" => "text", "version" => 1, "data" => {"body" => md}} unless md.empty?
        current_md = +""
      }

      pattern = /<!--\s*wp:([\w\/-]+)(\s+\{[^}]*\})?\s*(\/)?-->(?:(.*?)<!--\s*\/wp:\1\s*-->)?/m

      pos = 0
      html.scan(pattern) do |kind, attrs_json, _self_close, inner|
        match = Regexp.last_match
        current_md << gutenberg_to_markdown(html[pos...match.begin(0)]) if match.begin(0) > pos
        pos = match.end(0)

        case kind
        when "heading"
          if /<h2[^>]*>(.*?)<\/h2>/m =~ inner.to_s
            heading = strip_tags(Regexp.last_match(1)).strip
            flush_text.call
            current_md << "## #{heading}\n\n"
          else
            current_md << gutenberg_to_markdown(inner.to_s)
          end

        when "image"
          flush_text.call
          asset_id = wp_image_asset_id(attrs_json, inner, manifest)
          alt = (inner.to_s =~ /alt="([^"]*)"/) ? $1 : ""
          caption = (inner.to_s =~ /<figcaption[^>]*>(.*?)<\/figcaption>/m) ? strip_tags($1).strip : nil

          if asset_id
            data = {"asset_id" => asset_id.to_s, "alt" => alt}
            data["caption"] = caption if caption && !caption.empty?
            sections << {"type" => "image", "version" => 1, "data" => data}
          else
            # No mapping: a text block with the original URL, for an editor to fix.
            current_md << gutenberg_to_markdown(inner.to_s)
            flush_text.call
          end

        when "gallery"
          flush_text.call
          ids = wp_gallery_asset_ids(attrs_json, manifest)
          if ids.any?
            sections << {"type" => "gallery", "version" => 1, "data" => {"items" => ids.map { |id| {"asset_id" => id.to_s} }}}
          else
            current_md << gutenberg_to_markdown(inner.to_s)
            flush_text.call
          end

        else
          current_md << gutenberg_to_markdown(inner.to_s)
        end
      end

      current_md << gutenberg_to_markdown(html[pos..].to_s) if pos < html.length
      flush_text.call

      sections
    end

    def strip_tags(html)
      CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, ""))
    end

    # A wp:image block's Asset id: from the block's {"id":123}, else by its
    # wp-content URL.
    def wp_image_asset_id(attrs_json, inner, manifest)
      if attrs_json && (match = attrs_json.match(/"id"\s*:\s*(\d+)/)) && (entry = manifest[match[1]])
        return entry["asset_id"]
      end

      if (url = inner.to_s[/src="(https?:[^"]+)"/, 1])
        path = url.sub(%r{^.*/wp-content/uploads/}, "")
        manifest.each_value do |entry|
          return entry["asset_id"] if entry["path"] == path && entry["asset_id"]
        end
      end
      nil
    end

    def wp_gallery_asset_ids(attrs_json, manifest)
      ids = attrs_json && (match = attrs_json.match(/"ids"\s*:\s*\[([^\]]*)\]/)) ? match[1].scan(/\d+/) : []
      ids.filter_map { |id| manifest[id.to_s]&.dig("asset_id") }
    end
  end
end
