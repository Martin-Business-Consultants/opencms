# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry do
  let(:collection) {
    Collection.create!(slug: "blog-#{SecureRandom.hex(3)}", name: "Blog",
                       schema: {"fields" => [{"name" => "summary", "type" => "string"}]})
  }

  def make(attrs = {})
    described_class.create!({
      collection:    collection,
      slug:          "e-#{SecureRandom.hex(3)}",
      title:         "T",
      status:        "draft",
      locale:        "en",
      frontmatter:   {},
      body_markdown: ""
    }.merge(attrs))
  end

  it "requires title and slug" do
    e = described_class.new(collection: collection)
    e.valid?
    expect(e.errors).to include(:title, :slug)
  end

  it "enforces slug uniqueness within a collection" do
    a = make(slug: "first")
    dup = described_class.new(collection: collection, slug: "first", title: "x",
                              status: "draft", locale: "en", frontmatter: {}, body_markdown: "")
    expect(dup).not_to be_valid

    other = Collection.create!(slug: "shop", name: "Shop", schema: {"fields" => []})
    sibling = described_class.new(collection: other, slug: "first", title: "x",
                                   status: "draft", locale: "en", frontmatter: {}, body_markdown: "")
    expect(sibling).to be_valid
  end

  it "rejects frontmatter that doesn't match the collection schema" do
    invalid = described_class.new(
      collection: collection, slug: "x", title: "T", status: "draft", locale: "en",
      frontmatter: {"summary" => 123}, body_markdown: ""
    )
    expect(invalid).not_to be_valid
    expect(invalid.errors[:frontmatter].join).to match(/string/i)
  end

  describe "blocks" do
    let(:block_collection) {
      Collection.create!(slug: "states-#{SecureRandom.hex(3)}", name: "States",
                         enable_blocks: true, schema: {"fields" => []})
    }

    before do
      BlockType.create!(slug: "hero", label: "Hero", fields: [
        {"name" => "heading", "type" => "string", "required" => true}
      ])
    end

    def block_entry(attrs = {})
      described_class.new({
        collection: block_collection, slug: "s-#{SecureRandom.hex(3)}", title: "T",
        status: "draft", locale: "en", frontmatter: {}, body_markdown: ""
      }.merge(attrs))
    end

    it "defaults to an empty array" do
      expect(make.blocks).to eq([])
    end

    it "rejects a non-array blocks value" do
      e = block_entry(blocks: {"type" => "hero"})
      expect(e).not_to be_valid
      expect(e.errors[:blocks].join).to match(/must be an array/i)
    end

    it "rejects blocks on a collection that hasn't opted in" do
      e = described_class.new(
        collection: collection, slug: "x", title: "T", status: "draft", locale: "en",
        frontmatter: {}, body_markdown: "", blocks: [{"type" => "hero", "data" => {"heading" => "Hi"}}]
      )
      expect(e).not_to be_valid
      expect(e.errors[:blocks].join).to match(/not enabled/i)
    end

    it "accepts valid blocks when the collection enables them" do
      e = described_class.create!(
        collection: block_collection, slug: "ca", title: "California", status: "draft",
        locale: "en", frontmatter: {}, body_markdown: "",
        blocks: [{"type" => "hero", "data" => {"heading" => "Golden State"}}]
      )
      expect(e).to be_persisted
    end

    it "validates each block against its block type" do
      e = block_entry(blocks: [{"type" => "hero", "data" => {}}])
      expect(e).not_to be_valid
      expect(e.errors[:blocks].join).to match(/heading/i)
    end

    it "rejects unknown block types" do
      e = block_entry(blocks: [{"type" => "nope", "data" => {}}])
      expect(e).not_to be_valid
      expect(e.errors[:blocks].join).to match(/unknown type/i)
    end

    it "snapshots a version when blocks change" do
      e = described_class.create!(
        collection: block_collection, slug: "wa", title: "Washington", status: "draft",
        locale: "en", frontmatter: {}, body_markdown: "", blocks: []
      )
      expect {
        e.update!(blocks: [{"type" => "hero", "data" => {"heading" => "Evergreen"}}])
      }.to change { e.versions.count }.by(1)
      expect(e.versions.last.blocks).to eq([{"type" => "hero", "data" => {"heading" => "Evergreen"}}])
    end
  end
end
