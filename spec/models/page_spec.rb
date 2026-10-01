# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page do
  def make(attrs = {})
    described_class.create!({
      slug:        "p-#{SecureRandom.hex(3)}",
      title:       "T",
      status:      "draft",
      locale:      "en",
      blocks:      [],
      schema:      {"fields" => []},
      frontmatter: {},
      seo:         {}
    }.merge(attrs))
  end

  describe "validations" do
    it "requires title and slug" do
      page = described_class.new
      page.valid?
      expect(page.errors).to include(:title, :slug)
    end

    it "rejects unknown statuses" do
      expect(described_class.new(status: "weird")).not_to be_valid
    end

    it "rejects upper-case slugs" do
      page = make(slug: "BadSlug")
      expect(page).not_to be_valid
    rescue ActiveRecord::RecordInvalid
      # expected — make() uses create!, surface as failure
      page = described_class.new(slug: "BadSlug", title: "T", status: "draft", locale: "en",
                                  blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {})
      expect(page).not_to be_valid
    end
  end

  describe "path computation" do
    it "is the slug for top-level pages" do
      page = make(slug: "about")
      expect(page.path).to eq("about")
      expect(page.depth).to eq(0)
    end

    it "concatenates parent.path + slug for children" do
      parent = make(slug: "blog")
      child  = make(slug: "post-1", parent_id: parent.id)
      expect(child.path).to eq("blog/post-1")
      expect(child.depth).to eq(1)
    end
  end

  describe "uniqueness" do
    it "enforces unique slug per parent" do
      parent = make(slug: "section")
      make(slug: "child", parent_id: parent.id)
      dup = described_class.new(
        slug: "child", parent_id: parent.id, title: "x", status: "draft", locale: "en",
        blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {}
      )
      expect(dup).not_to be_valid
    end

    it "allows the same slug under different parents" do
      a = make(slug: "alpha")
      b = make(slug: "beta")
      make(slug: "x", parent_id: a.id)
      sibling_under_b = described_class.new(
        slug: "x", parent_id: b.id, title: "x", status: "draft", locale: "en",
        blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {}
      )
      expect(sibling_under_b).to be_valid
    end
  end
end
