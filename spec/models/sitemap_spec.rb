# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sitemap do
  def make_page(attrs = {})
    Page.create!({
      slug:        "p-#{SecureRandom.hex(3)}",
      title:       "A page",
      status:      "published",
      locale:      "en",
      blocks:      [],
      schema:      {"fields" => []},
      frontmatter: {},
      seo:         {}
    }.merge(attrs))
  end

  def make_collection
    Collection.create!(slug: "blog-#{SecureRandom.hex(3)}", name: "Blog", schema: {"fields" => []})
  end

  def make_entry(collection, attrs = {})
    CollectionEntry.create!({
      collection:    collection,
      slug:          "e-#{SecureRandom.hex(3)}",
      title:         "An entry",
      status:        "published",
      locale:        "en",
      frontmatter:   {},
      body_markdown: "",
      seo:           {}
    }.merge(attrs))
  end

  describe "#all_entries" do
    it "includes pages and collection entries with derived paths" do
      page = make_page(slug: "about")
      coll = make_collection
      entry = make_entry(coll, slug: "hello")

      sitemap = described_class.new
      paths = sitemap.all_entries.map(&:loc)

      expect(paths).to include("/about", "/#{coll.slug}/hello")
      page_entry = sitemap.all_entries.find { |e| e.id == page.id && e.source == "page" }
      expect(page_entry.changefreq).to eq("weekly")
      expect(page_entry.priority).to eq(0.7)

      ce = sitemap.all_entries.find { |e| e.id == entry.id && e.source == "collection_entry" }
      expect(ce.collection_slug).to eq(coll.slug)
      expect(ce.priority).to eq(0.5)
    end

    it "honors seo overrides for canonical, priority, and changefreq" do
      make_page(slug: "promo", seo: {
        "canonical"            => "https://other.example.com/promo",
        "sitemap_priority"     => "0.9",
        "sitemap_changefreq"   => "daily"
      })

      e = described_class.new.all_entries.find { |x| x.source == "page" }
      expect(e.loc).to eq("https://other.example.com/promo")
      expect(e.priority).to eq(0.9)
      expect(e.changefreq).to eq("daily")
    end

    it "reads the canonical_url key the admin SEO panel saves" do
      make_page(slug: "promo", seo: {"canonical_url" => "https://other.example.com/promo"})

      e = described_class.new.all_entries.find { |x| x.source == "page" }
      expect(e.loc).to eq("https://other.example.com/promo")
    end

    it "prefers canonical_url over the legacy canonical key" do
      make_page(slug: "promo", seo: {
        "canonical_url" => "https://new.example.com/promo",
        "canonical"     => "https://old.example.com/promo"
      })

      e = described_class.new.all_entries.find { |x| x.source == "page" }
      expect(e.loc).to eq("https://new.example.com/promo")
    end

    it "falls back to the legacy canonical key when canonical_url is blank" do
      make_page(slug: "promo", seo: {"canonical_url" => "  ", "canonical" => "https://old.example.com/promo"})

      e = described_class.new.all_entries.find { |x| x.source == "page" }
      expect(e.loc).to eq("https://old.example.com/promo")
    end

    it "clamps priority into [0, 1] and ignores invalid changefreq" do
      make_page(slug: "x", seo: {"sitemap_priority" => "5", "sitemap_changefreq" => "bogus"})
      e = described_class.new.all_entries.first
      expect(e.priority).to eq(1.0)
      expect(e.changefreq).to eq("weekly")
    end

    it "treats home page as priority 1.0 by default" do
      make_page(slug: "home", title: "Home")
      e = described_class.new.all_entries.find { |x| x.slug == "home" }
      expect(e.priority).to eq(1.0)
    end
  end

  describe "#entries" do
    it "excludes drafts, archived, and noindex records" do
      pub      = make_page(slug: "pub")
      _draft   = make_page(slug: "drafty", status: "draft")
      _archive = make_page(slug: "old", status: "archived")
      _hidden  = make_page(slug: "hidden", seo: {"noindex" => true})

      paths = described_class.new.entries.map(&:loc)
      expect(paths).to contain_exactly("/#{pub.slug}")
    end
  end

  describe "#absolute_url" do
    it "puts the site's base URL in front of a path" do
      expect(described_class.new.absolute_url("/x", "https://example.com/")).to eq("https://example.com/x")
    end

    it "leaves a path as it is when no base URL is configured" do
      expect(described_class.new.absolute_url("/x", "")).to eq("/x")
    end

    it "leaves an absolute canonical alone" do
      expect(described_class.new.absolute_url("https://elsewhere.test/c", "https://example.com")).to eq("https://elsewhere.test/c")
    end
  end
end
