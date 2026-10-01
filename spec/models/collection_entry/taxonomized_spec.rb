# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry::Taxonomized do
  let(:categories) { Collection.create!(slug: "categories", name: "Categories", schema: {"fields" => []}) }
  let(:news) { categories.entries.create!(slug: "news", title: "News", status: "published") }

  it "takes a category from its collection's pool" do
    posts = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}, categories_collection: categories)

    entry = posts.entries.create!(slug: "a", title: "A", status: "draft", category: news)

    expect(entry.category_pool).to eq(categories)
    expect(entry.category).to eq(news)
  end

  it "refuses a category when its collection has no pool" do
    posts = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})

    entry = posts.entries.new(slug: "a", title: "A", status: "draft", category: news)

    expect(entry).not_to be_valid
    expect(entry.errors[:category]).to be_present
  end
end
