# frozen_string_literal: true

require "rails_helper"

RSpec.describe Revision::Diff do
  let(:author) { create(:user) }

  # Page validates its blocks against the registered types, so the fixtures
  # need real ones.
  before do
    {
      "hero" => [{"name" => "heading", "type" => "string"}],
      "cta"  => [{"name" => "label",   "type" => "string"}],
      "text" => [{"name" => "body",    "type" => "text"}]
    }.each do |slug, fields|
      BlockType.find_or_create_by!(slug: slug) { |bt| bt.label = slug.titleize; bt.fields = fields }
    end
  end

  def make_page(attrs = {})
    Page.create!({
      slug: "p-#{SecureRandom.hex(3)}",
      title: "T",
      status: "published",
      locale: "en",
      blocks: [],
      schema: {"fields" => []},
      frontmatter: {},
      seo: {}
    }.merge(attrs))
  end

  def diff_for(page, attributes)
    Revision.propose!(record: page, attributes: attributes, author: author).diff
  end

  def field(diff, key) = diff[:fields].find { |f| f[:key] == key }

  it "shows a short scalar as before and after" do
    page = make_page(title: "Old")
    f = field(diff_for(page, {"title" => "New"}), "title")

    expect(f[:kind]).to eq("text")
    expect(f).to include(before: "Old", after: "New")
  end

  it "diffs an object field key by key" do
    page = make_page(seo: {"title" => "A", "description" => "keep"})
    f = field(diff_for(page, {"seo" => {"title" => "B", "description" => "keep", "og_image" => "x.jpg"}}), "seo")

    expect(f[:kind]).to eq("object")
    expect(f[:entries].map { |e| [e[:key], e[:op]] }).to contain_exactly(
      ["title", "changed"], ["og_image", "added"]
    )
  end

  describe "blocks" do
    let(:hero)  { {"id" => "b1", "type" => "hero", "data" => {"heading" => "Hello"}} }
    let(:cta)   { {"id" => "b2", "type" => "cta",  "data" => {"label" => "Call"}} }
    let(:extra) { {"id" => "b3", "type" => "text", "data" => {"body" => "New"}} }

    it "separates a move from a rewrite" do
      page = make_page(blocks: [hero, cta])
      f = field(diff_for(page, {"blocks" => [cta, hero]}), "blocks")

      expect(f[:blocks].map { |b| [b[:id], b[:op]] }).to contain_exactly(
        ["b2", "moved"], ["b1", "moved"]
      )
    end

    it "reports an edited block's changed keys only" do
      page = make_page(blocks: [hero, cta])
      edited = {"id" => "b1", "type" => "hero", "data" => {"heading" => "Goodbye"}}
      f = field(diff_for(page, {"blocks" => [edited, cta]}), "blocks")

      changed = f[:blocks].find { |b| b[:id] == "b1" }
      expect(changed[:op]).to eq("changed")
      expect(changed[:fields].map { |e| e[:key] }).to eq(["heading"])

      untouched = f[:blocks].find { |b| b[:id] == "b2" }
      expect(untouched[:op]).to eq("unchanged")
    end

    it "reports additions and removals" do
      page = make_page(blocks: [hero, cta])
      f = field(diff_for(page, {"blocks" => [hero, extra]}), "blocks")

      by_op = f[:blocks].to_h { |b| [b[:id], b[:op]] }
      expect(by_op["b3"]).to eq("added")
      expect(by_op["b2"]).to eq("removed")
    end
  end

  it "collapses untouched context in a long text diff" do
    before = (1..40).map { |i| "line #{i}" }.join("\n")
    after  = before.sub("line 20", "line twenty")
    page = make_page(slug: "p-lines")
    entry_diff = field(diff_for(page, {"seo" => {"body" => after}}), "seo")
    expect(entry_diff).to be_present # object fields render whole values

    # body_markdown on an entry takes the line-diff path
    collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    entry = collection.entries.create!(
      slug: "e1", title: "T", status: "published", locale: "en",
      body_markdown: before, frontmatter: {}, seo: {}
    )
    f = Revision.propose!(record: entry, attributes: {"body_markdown" => after}, author: author)
      .diff[:fields].find { |x| x[:key] == "body_markdown" }

    expect(f[:kind]).to eq("lines")
    expect(f[:lines].count { |l| l[:op] == "skip" }).to be >= 1
    expect(f[:lines].map { |l| l[:text] }).to include("line twenty")
  end

  it "flags a revision whose record moved underneath it" do
    page = make_page(title: "Old")
    revision = Revision.propose!(record: page, attributes: {"title" => "New"}, author: author)
    page.update!(title: "Someone else")

    diff = revision.reload.diff
    expect(diff[:stale]).to be(true)
    expect(diff[:drifted]).to eq(["title"])
  end
end
