# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry::Referencing do
  it "records what its fields link to, rewritten on each save" do
    team = Collection.create!(slug: "team", name: "Team", schema: {"fields" => []})
    ada = team.entries.create!(slug: "ada", title: "Ada", status: "published")
    posts = Collection.create!(slug: "posts", name: "Posts",
      schema: {"fields" => [{"name" => "author", "type" => "record_ref", "of_collection" => "team"}]})
    post = posts.entries.create!(slug: "hello", title: "Hello", status: "draft", frontmatter: {"author" => ada.id.to_s})

    expect(post.content_references.pluck(:ref_id, :position)).to eq([[ada.id.to_s, -1]])

    post.update!(frontmatter: {})
    expect(post.content_references.reload).to be_empty
  end
end
