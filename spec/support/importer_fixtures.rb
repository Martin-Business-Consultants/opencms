# frozen_string_literal: true

require "sqlite3"

# Small, offline sources for the WordPress and Directus importers: a WXR
# export with one of each post type the pipeline knows, and a Directus
# SQLite export with a page (M2A blocks), a section, a collection and a
# singleton. Nothing here touches the network; the WordPress media stage's
# download is stubbed by the caller (stub_wordpress_downloads).
module ImporterFixtures
  # A 1x1 PNG, for the media the WordPress export points at.
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")

  def write_wordpress_export(dir)
    path = File.join(dir, "export.xml")
    File.write(path, <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:wp="http://wordpress.org/export/1.2/">
        <channel>
          <item>
            <title>Hop field</title>
            <wp:post_id>10</wp:post_id>
            <wp:post_type>attachment</wp:post_type>
            <wp:attachment_url>https://oldmill.example/wp-content/uploads/2024/01/hops.png</wp:attachment_url>
            <wp:postmeta><wp:meta_key>_wp_attached_file</wp:meta_key><wp:meta_value>2024/01/hops.png</wp:meta_value></wp:postmeta>
            <wp:postmeta><wp:meta_key>_wp_attachment_image_alt</wp:meta_key><wp:meta_value>Hops on the bine</wp:meta_value></wp:postmeta>
          </item>
          <item>
            <title>Mill Pond IPA</title>
            <wp:post_id>20</wp:post_id>
            <wp:post_name>mill-pond-ipa</wp:post_name>
            <wp:post_type>beer</wp:post_type>
            <wp:status>publish</wp:status>
            <wp:post_date_gmt>2024-03-01 12:00:00</wp:post_date_gmt>
            <content:encoded><![CDATA[<!-- wp:paragraph --><p>Bright &amp; <strong>bitter</strong>.</p><!-- /wp:paragraph -->]]></content:encoded>
            <category domain="beer-style" nicename="ipa"><![CDATA[IPA]]></category>
            <wp:postmeta><wp:meta_key>abv</wp:meta_key><wp:meta_value>6.4</wp:meta_value></wp:postmeta>
            <wp:postmeta><wp:meta_key>_thumbnail_id</wp:meta_key><wp:meta_value>10</wp:meta_value></wp:postmeta>
            <wp:postmeta><wp:meta_key>_yoast_wpseo_metadesc</wp:meta_key><wp:meta_value>Our flagship IPA.</wp:meta_value></wp:postmeta>
          </item>
          <item>
            <title>Pretzel Bites</title>
            <wp:post_id>30</wp:post_id>
            <wp:post_name>pretzel-bites</wp:post_name>
            <wp:post_type>food</wp:post_type>
            <wp:status>publish</wp:status>
            <wp:post_date_gmt>2024-03-02 12:00:00</wp:post_date_gmt>
            <content:encoded><![CDATA[<p>Warm, with beer cheese.</p>]]></content:encoded>
            <category domain="post_tag" nicename="appetizers"><![CDATA[Appetizers]]></category>
            <category domain="category" nicename="daily"><![CDATA[Daily]]></category>
          </item>
          <item>
            <title>Pretzel Bites</title>
            <wp:post_id>40</wp:post_id>
            <wp:post_name>pretzel-bites-special</wp:post_name>
            <wp:post_type>special</wp:post_type>
            <wp:status>publish</wp:status>
            <wp:post_date_gmt>2024-03-06 12:00:00</wp:post_date_gmt>
            <content:encoded><![CDATA[]]></content:encoded>
            <category domain="category" nicename="wednesday"><![CDATA[Wednesday]]></category>
            <wp:postmeta><wp:meta_key>_yoast_wpseo_metadesc</wp:meta_key><wp:meta_value>Half off all night.</wp:meta_value></wp:postmeta>
          </item>
          <item>
            <title>About us</title>
            <wp:post_id>50</wp:post_id>
            <wp:post_name>about</wp:post_name>
            <wp:post_type>page</wp:post_type>
            <wp:status>publish</wp:status>
            <wp:post_date_gmt>2024-01-15 12:00:00</wp:post_date_gmt>
            <content:encoded><![CDATA[<!-- wp:paragraph --><p>Brewing since 1998.</p><!-- /wp:paragraph --><!-- wp:heading --><h2>The mill</h2><!-- /wp:heading --><!-- wp:paragraph --><p>On the river.</p><!-- /wp:paragraph --><!-- wp:image {"id":10} --><figure><img src="https://oldmill.example/wp-content/uploads/2024/01/hops.png" alt="Hops"/><figcaption>Our hops</figcaption></figure><!-- /wp:image -->]]></content:encoded>
          </item>
          <item>
            <title>Beers</title>
            <wp:post_id>60</wp:post_id>
            <wp:post_name>beers</wp:post_name>
            <wp:post_type>page</wp:post_type>
            <wp:status>publish</wp:status>
            <wp:post_parent>50</wp:post_parent>
            <wp:post_date_gmt>2024-01-16 12:00:00</wp:post_date_gmt>
            <content:encoded><![CDATA[]]></content:encoded>
          </item>
        </channel>
      </rss>
    XML
    path
  end

  # URI#open is what the media stage downloads with; answer every request
  # with the fixture PNG instead of reaching the network.
  def stub_wordpress_downloads
    allow_any_instance_of(URI::HTTPS).to receive(:open) { |*, **, &block| block.call(StringIO.new(PNG)) }
  end

  def write_directus_export(dir)
    path = File.join(dir, "directus.db")
    db = SQLite3::Database.new(path)
    db.execute_batch(<<~SQL)
      CREATE TABLE directus_collections (collection varchar, singleton boolean, hidden boolean, note text, icon varchar);
      CREATE TABLE directus_fields (collection varchar, field varchar, special varchar, interface varchar, options text, note text, required boolean, readonly boolean, hidden boolean, sort integer, "group" varchar);
      CREATE TABLE directus_relations (many_collection varchar, many_field varchar, one_collection varchar, one_field varchar, one_collection_field varchar, one_allowed_collections varchar, junction_field varchar);

      CREATE TABLE pages (id char(36), title varchar, slug varchar, status varchar, date_created timestamp);
      CREATE TABLE pages_blocks (id integer, pages_id char(36), item varchar, collection varchar, sort integer);
      CREATE TABLE block_hero (id char(36), heading varchar, body text);
      CREATE TABLE posts (id char(36), title varchar, slug varchar, status varchar, body text, date_created timestamp);
      CREATE TABLE site_settings (id integer, site_name varchar, tagline varchar);

      INSERT INTO directus_collections VALUES ('pages', 0, 0, NULL, NULL), ('pages_blocks', 0, 1, NULL, NULL), ('block_hero', 0, 1, NULL, NULL), ('posts', 0, 0, NULL, NULL), ('site_settings', 1, 0, NULL, NULL);

      INSERT INTO directus_fields VALUES
        ('pages', 'id', 'uuid', NULL, NULL, NULL, 0, 1, 1, 1, NULL),
        ('pages', 'title', NULL, 'input', NULL, NULL, 1, 0, 0, 2, NULL),
        ('pages', 'slug', NULL, 'input', NULL, NULL, 0, 0, 0, 3, NULL),
        ('pages', 'status', NULL, 'select-dropdown', NULL, NULL, 0, 0, 0, 4, NULL),
        ('pages', 'blocks', 'm2a', 'list-m2a', NULL, NULL, 0, 0, 0, 5, NULL),
        ('pages_blocks', 'id', NULL, NULL, NULL, NULL, 0, 1, 1, 1, NULL),
        ('pages_blocks', 'pages_id', NULL, NULL, NULL, NULL, 0, 0, 1, 2, NULL),
        ('pages_blocks', 'item', NULL, NULL, NULL, NULL, 0, 0, 1, 3, NULL),
        ('pages_blocks', 'collection', NULL, NULL, NULL, NULL, 0, 0, 1, 4, NULL),
        ('pages_blocks', 'sort', NULL, NULL, NULL, NULL, 0, 0, 1, 5, NULL),
        ('block_hero', 'id', 'uuid', NULL, NULL, NULL, 0, 1, 1, 1, NULL),
        ('block_hero', 'heading', NULL, 'input', NULL, NULL, 0, 0, 0, 2, NULL),
        ('block_hero', 'body', NULL, 'input-multiline', NULL, NULL, 0, 0, 0, 3, NULL),
        ('posts', 'id', 'uuid', NULL, NULL, NULL, 0, 1, 1, 1, NULL),
        ('posts', 'title', NULL, 'input', NULL, NULL, 1, 0, 0, 2, NULL),
        ('posts', 'slug', NULL, 'input', NULL, NULL, 0, 0, 0, 3, NULL),
        ('posts', 'status', NULL, 'select-dropdown', NULL, NULL, 0, 0, 0, 4, NULL),
        ('posts', 'body', NULL, 'input-rich-text-md', NULL, NULL, 0, 0, 0, 5, NULL),
        ('site_settings', 'id', NULL, NULL, NULL, NULL, 0, 1, 1, 1, NULL),
        ('site_settings', 'site_name', NULL, 'input', NULL, NULL, 0, 0, 0, 2, NULL),
        ('site_settings', 'tagline', NULL, 'input', NULL, NULL, 0, 0, 0, 3, NULL);

      INSERT INTO directus_relations VALUES
        ('pages_blocks', 'pages_id', 'pages', 'blocks', NULL, NULL, 'item'),
        ('pages_blocks', 'item', NULL, NULL, 'collection', 'block_hero', 'pages_id');

      INSERT INTO pages VALUES ('11111111-1111-1111-1111-111111111111', 'Home', 'home', 'published', '2024-02-01 10:00:00');
      INSERT INTO block_hero VALUES ('22222222-2222-2222-2222-222222222222', 'Welcome to the mill', 'Fresh beer, every day.');
      INSERT INTO pages_blocks VALUES (1, '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'block_hero', 1);
      INSERT INTO posts VALUES ('33333333-3333-3333-3333-333333333333', 'Grand opening', 'grand-opening', 'published', 'We are *open*.', '2024-02-02 10:00:00'),
                               ('44444444-4444-4444-4444-444444444444', 'Draft notes', NULL, 'draft', 'Soon.', '2024-02-03 10:00:00');
      INSERT INTO site_settings VALUES (1, 'Old Mill', 'Brewpub & grill');
    SQL
    db.close
    path
  end

  # Everything an import writes, with ids replaced by what they point at,
  # so two runs compare equal regardless of primary keys.
  def importer_state
    asset_ref = ->(id) { (asset = Asset.find_by(id: id)) ? "asset:#{asset.name}" : id }
    deep = ->(value) do
      case value
      when Hash then value.to_h { |k, v| [k, (%w[asset_id featured_image og_image].include?(k.to_s) ? asset_ref.(v) : deep.(v))] }
      when Array then value.map { deep.(it) }
      else value
      end
    end

    {
      collections: Collection.order(:slug).map do |c|
        {slug: c.slug, name: c.name, schema: c.schema, categories: c.categories_collection&.slug, tags: c.tags_collection&.slug}
      end,
      entries: CollectionEntry.includes(:collection).order(:id).map do |e|
        {collection: e.collection.slug, slug: e.slug, title: e.title, status: e.status, frontmatter: deep.(e.frontmatter),
         body: e.body_markdown, published_at: e.published_at&.iso8601, category: e.category&.slug,
         tags: e.respond_to?(:tags) ? Array(e.tags).map { it.respond_to?(:slug) ? it.slug : it } : nil, seo: deep.(e.seo)}
      end,
      pages: Page.order(:path).map do |p|
        {path: p.path, title: p.title, status: p.status, blocks: deep.(p.blocks), seo: deep.(p.seo),
         frontmatter: p.frontmatter, parent: p.parent&.path, published_at: p.published_at&.iso8601}
      end,
      block_types: BlockType.order(:slug).map { {slug: it.slug, label: it.label, fields: it.fields} },
      globals: Global.order(:slug).map { {slug: it.slug, name: it.name, schema: it.schema, data: deep.(it.data)} },
      assets: Asset.order(:name).map { {name: it.name, folder: it.folder, filename: it.file.filename.to_s, bytes: it.file.byte_size} }
    }
  end
end

RSpec.configure { |config| config.include ImporterFixtures }
