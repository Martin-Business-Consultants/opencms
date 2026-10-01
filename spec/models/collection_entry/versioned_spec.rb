# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry::Versioned do
  it "keeps a snapshot of each content change, not of a rename" do
    collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => [{"name" => "summary", "type" => "string"}]})
    entry = collection.entries.create!(slug: "a", title: "A", status: "draft", frontmatter: {"summary" => "one"})

    entry.update!(frontmatter: {"summary" => "two"})
    entry.update!(title: "Renamed")

    expect(entry.versions.map { it.frontmatter["summary"] }).to eq(%w[one two])
  end
end
