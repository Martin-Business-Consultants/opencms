# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry::Searchable do
  def indexed(id) = ActiveRecord::Base.connection.select_value("SELECT title FROM collection_entries_fts WHERE rowid = #{id.to_i}")

  it "indexes its body and fields, and drops out when destroyed" do
    collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => [{"name" => "summary", "type" => "string"}]})
    entry = collection.entries.create!(slug: "a", title: "Alpha", status: "draft", body_markdown: "Body text", frontmatter: {"summary" => "Short"})

    expect(entry.search_text).to include("Body text", "Short")
    expect(indexed(entry.id)).to eq("Alpha")

    entry.destroy_permanently!
    expect(indexed(entry.id)).to be_nil
  end
end
