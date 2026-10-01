# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry::Composed do
  it "keeps blocks out of a collection that hasn't turned them on" do
    posts = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})

    entry = posts.entries.new(slug: "a", title: "A", status: "draft", blocks: [{"id" => "b1", "type" => "text", "data" => {}}])

    expect(entry).not_to be_enable_blocks
    expect(entry).not_to be_valid
    expect(entry.errors[:blocks]).to include("are not enabled for this collection")
  end

  it "checks frontmatter against its collection's fields" do
    posts = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => [{"name" => "count", "type" => "integer"}]})

    entry = posts.entries.new(slug: "a", title: "A", status: "draft", frontmatter: {"count" => "many"})

    expect(entry).not_to be_valid
    expect(entry.errors[:frontmatter].join).to include("count")
  end
end
