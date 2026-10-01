# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::BlockExpansion do
  let(:posts) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }

  def list(data) = described_class.new([{"type" => "collection_list", "data" => data}]).blocks.first["resolved"]

  it "fills a collection list with its published entries, sorted and limited" do
    posts.entries.create!(slug: "old", title: "Old", status: "published", published_at: 2.days.ago, locale: "en")
    posts.entries.create!(slug: "new", title: "New", status: "published", published_at: 1.day.ago, locale: "en")
    posts.entries.create!(slug: "draft", title: "Draft", status: "draft", locale: "en")

    resolved = list("collection_slug" => "posts", "sort_by" => "published_at", "sort_dir" => "desc", "limit" => 1)

    expect(resolved["entries"].map { it["slug"] }).to eq(%w[new])
    expect(resolved["total"]).to eq(2)
    expect(resolved["collection"]).to eq("slug" => "posts", "name" => "Posts")
  end

  it "says so when the collection doesn't exist" do
    expect(list("collection_slug" => "nope")).to eq("error" => "collection not found", "slug" => "nope", "entries" => [], "total" => 0)
  end

  it "fills contact details and leaves other blocks alone" do
    Setting.set("general", {"email" => "hi@example.com"})
    blocks = described_class.new([{"type" => "contact_info"}, {"type" => "hero", "data" => {}}, "junk"]).blocks

    expect(blocks[0]["resolved"]).to eq("contact" => Setting.get("general"))
    expect(blocks[1..]).to eq([{"type" => "hero", "data" => {}}, "junk"])
  end
end
