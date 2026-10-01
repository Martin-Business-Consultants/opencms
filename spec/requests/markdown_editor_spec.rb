# frozen_string_literal: true

require "rails_helper"

# Decision 8: markdown fields (and an entry's body) are edited as Markdown,
# with a server-drawn preview, and stored as typed.
RSpec.describe "Markdown fields", type: :request do
  let(:admin) { create(:user) }
  let(:collection) { Collection.create!(slug: "notes", name: "Notes", schema: {"fields" => [{"name" => "summary", "type" => "markdown"}]}) }

  before { sign_in_as admin }

  it "renders a preview on the server, without raw HTML" do
    post markdown_preview_path, params: {text: "# Hello\n\n**bold** <script>alert(1)</script>"}

    expect(response.body).to include("<h1>Hello</h1>", "<strong>bold</strong>")
    expect(response.body).not_to include("<script")
  end

  it "keeps GitHub tables, strikethrough and task lists in the preview" do
    post markdown_preview_path, params: {text: "| a | b |\n|---|---|\n| 1 | 2 |\n\n~~old~~\n\n- [x] done"}

    expect(response.body).to include("<table>", "<td>1</td>", "<del>old</del>", %(type="checkbox"))
  end

  it "edits a markdown field and the entry body in a Markdown textarea" do
    entry = collection.entries.create!(slug: "one", title: "One", status: "draft", frontmatter: {"summary" => "*hi*"}, body_markdown: "Body **text**")

    get edit_collection_entry_path(collection.slug, entry.slug)

    expect(response.body).to include("markdown-editor", "*hi*", "Body **text**")
  end

  it "stores Markdown as typed, and an untouched CRLF-posted body is not a change" do
    entry = collection.entries.create!(slug: "two", title: "Two", status: "draft", frontmatter: {"summary" => "a\nb"}, body_markdown: "line one\nline two")
    stamp = entry.updated_at

    patch collection_entry_path(collection.slug, entry.slug),
      params: {entry: {title: "Two", body_markdown: "line one\r\nline two", frontmatter: {"summary" => "a\r\nb"}}}

    entry.reload
    expect(entry.body_markdown).to eq("line one\nline two")
    expect(entry.frontmatter["summary"]).to eq("a\nb")
    expect(entry.updated_at).to eq(stamp)
  end
end
