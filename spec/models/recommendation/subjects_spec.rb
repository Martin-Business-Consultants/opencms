# frozen_string_literal: true

require "rails_helper"

RSpec.describe Recommendation::Subjects do
  let!(:page) { Page.create!(slug: "pricing", title: "Pricing", status: "published", locale: "en") }
  let!(:collection) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }
  let!(:entry) { collection.entries.create!(slug: "hello", title: "Hello", status: "published", locale: "en") }

  it "finds a page by path or id" do
    expect(Recommendation.find_subject(type: "Page", path: "pricing")).to eq(page)
    expect(Recommendation.find_subject(type: "Page", id: page.id)).to eq(page)
  end

  it "finds an entry by collection and slug, or id" do
    expect(Recommendation.find_subject(type: "CollectionEntry", collection: "posts", slug: "hello")).to eq(entry)
    expect(Recommendation.find_subject(type: "CollectionEntry", id: entry.id)).to eq(entry)
  end

  it "has no subject for what doesn't exist yet, rather than failing" do
    expect(Recommendation.find_subject(type: "Page", path: "teams")).to be_nil
    expect(Recommendation.find_subject(type: "CollectionEntry", collection: "nope", slug: "x")).to be_nil
    expect(Recommendation.find_subject(type: "User", id: 1)).to be_nil
    expect(Recommendation.find_subject).to be_nil
  end
end
