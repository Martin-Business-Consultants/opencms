# frozen_string_literal: true

require "rails_helper"

# The generic WordPress importer (decision 11): media, the site's title,
# posts with their categories, tags, featured image and author, and pages.
# Old Mill's custom post types are Importers::OldMillImport's.
RSpec.describe Importers::WordpressImport do
  let(:dir) { Dir.mktmpdir("wp-generic") }
  let(:dest) { File.join(dir, "out") }
  let(:quiet) { StringIO.new }
  let(:xml) do
    File.join(dir, "blog.xml").tap do |path|
      File.write(path, <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:wp="http://wordpress.org/export/1.2/">
          <channel>
            <title>Acme Journal</title>
            <description>Notes from the workshop</description>
            <wp:author><wp:author_login>ann</wp:author_login><wp:author_display_name><![CDATA[Ann Author]]></wp:author_display_name></wp:author>
            <item>
              <title>Hop field</title>
              <wp:post_id>10</wp:post_id>
              <wp:post_type>attachment</wp:post_type>
              <wp:attachment_url>https://oldmill.example/wp-content/uploads/2024/01/hops.png</wp:attachment_url>
              <wp:postmeta><wp:meta_key>_wp_attached_file</wp:meta_key><wp:meta_value>2024/01/hops.png</wp:meta_value></wp:postmeta>
            </item>
            <item>
              <title>Hello world</title>
              <dc:creator>ann</dc:creator>
              <wp:post_id>30</wp:post_id>
              <wp:post_name>hello-world</wp:post_name>
              <wp:post_type>post</wp:post_type>
              <wp:status>publish</wp:status>
              <wp:post_date_gmt>2024-05-01 09:00:00</wp:post_date_gmt>
              <content:encoded><![CDATA[<!-- wp:paragraph --><p>First &amp; <strong>best</strong>.</p><!-- /wp:paragraph -->]]></content:encoded>
              <excerpt:encoded><![CDATA[<p>A short hello.</p>]]></excerpt:encoded>
              <category domain="category" nicename="news"><![CDATA[News]]></category>
              <category domain="post_tag" nicename="launch"><![CDATA[Launch]]></category>
              <wp:postmeta><wp:meta_key>_thumbnail_id</wp:meta_key><wp:meta_value>10</wp:meta_value></wp:postmeta>
            </item>
            <item>
              <title>Draft thoughts</title>
              <dc:creator>ann</dc:creator>
              <wp:post_id>31</wp:post_id>
              <wp:post_name>draft-thoughts</wp:post_name>
              <wp:post_type>post</wp:post_type>
              <wp:status>draft</wp:status>
              <content:encoded><![CDATA[<p>Not yet.</p>]]></content:encoded>
            </item>
            <item>
              <title>About</title>
              <wp:post_id>40</wp:post_id>
              <wp:post_name>about</wp:post_name>
              <wp:post_type>page</wp:post_type>
              <wp:status>publish</wp:status>
              <content:encoded><![CDATA[<!-- wp:paragraph --><p>Who we are.</p><!-- /wp:paragraph -->]]></content:encoded>
            </item>
          </channel>
        </rss>
      XML
    end
  end

  before do
    BlockType.seed
    stub_wordpress_downloads
  end

  after { FileUtils.rm_rf(dir) }

  def run(stage = :all, **options)
    described_class.new(xml, dest, out: quiet, err: quiet, **options).public_send(stage)
  end

  it "imports posts with their taxonomy, image and author, pages, and the site's title" do
    run

    posts = Collection.find_by(slug: "posts")
    hello = posts.entries.find_by(slug: "hello-world")
    expect(hello).to have_attributes(status: "published", title: "Hello world", body_markdown: "First & **best**.")
    expect(hello.published_at).to eq(Time.utc(2024, 5, 1, 9))
    expect(hello.frontmatter).to include("author" => "Ann Author", "excerpt" => "A short hello.",
      "featured_image" => Asset.find_by(name: "Hop field").id.to_s)
    expect(hello.category.slug).to eq("news")
    expect(hello.tags.map(&:slug)).to eq(["launch"])
    expect(posts.categories_collection.slug).to eq("post-categories")
    expect(posts.entries.find_by(slug: "draft-thoughts").status).to eq("draft")

    expect(Page.find_by(slug: "about")).to be_present
    expect(Setting.get("general")).to include("title" => "Acme Journal", "description" => "Notes from the workshop")
    expect(Collection.where(slug: %w[beers food specials])).to be_empty
  end

  it "leaves a site title that's already set alone, and re-imports to the same records" do
    Setting.set("general", Setting.get("general").merge("title" => "Our own name"))
    run
    expect(Setting.get("general")["title"]).to eq("Our own name")

    expect { run }.not_to change { [CollectionEntry.count, Page.count, Collection.count, Asset.count] }
  end
end
