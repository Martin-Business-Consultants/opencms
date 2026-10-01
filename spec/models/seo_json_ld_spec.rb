# frozen_string_literal: true

require "rails_helper"

# JSON-LD ships inside a <script type="application/ld+json"> on the public page.
# Malformed markup fails silently — nothing errors, the rich result just never
# appears — so the contract is enforced at write time, on both Page and
# CollectionEntry via ContentValidators.
RSpec.describe "seo.json_ld validation" do
  def make_page(json_ld)
    Page.new(
      slug: "p-#{SecureRandom.hex(3)}", title: "T", status: "draft", locale: "en",
      blocks: [], schema: {"fields" => []}, frontmatter: {},
      seo: {"json_ld" => json_ld}
    )
  end

  it "accepts a single typed node" do
    page = make_page({"@context" => "https://schema.org", "@type" => "LocalBusiness"})
    expect(page).to be_valid
  end

  it "accepts an array of typed nodes" do
    page = make_page([{"@type" => "FAQPage"}, {"@type" => "BreadcrumbList"}])
    expect(page).to be_valid
  end

  it "accepts an @graph wrapper in place of a top-level @type" do
    page = make_page({"@context" => "https://schema.org", "@graph" => [{"@type" => "Organization"}]})
    expect(page).to be_valid
  end

  it "accepts a page with no json_ld at all" do
    expect(make_page(nil)).to be_valid
  end

  it "rejects a node with no @type" do
    page = make_page({"name" => "Untyped"})
    expect(page).not_to be_valid
    expect(page.errors[:seo].join).to match(/@type/)
  end

  it "rejects one untyped node among typed ones" do
    page = make_page([{"@type" => "FAQPage"}, {"name" => "oops"}])
    expect(page).not_to be_valid
  end

  it "rejects a scalar" do
    page = make_page("just a string")
    expect(page).not_to be_valid
    expect(page.errors[:seo].join).to match(/object/)
  end

  it "applies to collection entries too" do
    collection = Collection.create!(slug: "posts-#{SecureRandom.hex(3)}", name: "Posts")
    entry = collection.entries.new(
      slug: "e-#{SecureRandom.hex(3)}", title: "T", status: "draft", locale: "en",
      body_markdown: "", frontmatter: {}, blocks: [],
      seo: {"json_ld" => {"name" => "Untyped"}}
    )
    expect(entry).not_to be_valid
    expect(entry.errors[:seo].join).to match(/@type/)
  end
end
