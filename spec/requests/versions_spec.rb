# frozen_string_literal: true

require "rails_helper"

# Revisions › Browse: a page's or entry's saved versions, each compared with
# the record now, and restored through the editor's own save (and its review
# gate).
RSpec.describe "Versions", type: :request do
  let(:admin) { create(:user) }

  before { BlockType.seed }

  def make_page(**attrs)
    Page.create!({slug: "about", title: "About", status: "draft", locale: "en",
                  blocks: [{"id" => "b1", "type" => "text", "data" => {"body" => "First"}}]}.merge(attrs))
  end

  def edit_blocks(page, body)
    page.update!(blocks: [{"id" => "b1", "type" => "text", "data" => {"body" => body}}])
  end

  it "lists a page's versions and links them from the Publish box" do
    sign_in_as admin
    page = make_page
    edit_blocks(page, "Second")

    get edit_page_path(page.path)
    expect(response.body).to include(page_versions_path(page.path), "Browse")

    get page_versions_path(page.path)
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Revisions of “About”", "Same as now", "Blocks")
  end

  it "shows what restoring a version would change, and restores it" do
    sign_in_as admin
    page = make_page
    first = page.versions.newest_first.last
    edit_blocks(page, "Second")

    get page_version_path(page.path, first)
    expect(response.body).to include("Restore this version", "First", "Second")

    post page_version_restoration_path(page.path, first)
    expect(response).to redirect_to(edit_page_path(page.path))
    expect(page.reload.blocks.first.dig("data", "body")).to eq("First")
  end

  it "files a live page's restore as a revision for a role that can't publish" do
    page = make_page(status: "published")
    first = page.versions.newest_first.last
    edit_blocks(page, "Second")
    sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write]))

    get page_version_path(page.path, first)
    expect(response.body).to include("Submit this version for review")

    expect { post page_version_restoration_path(page.path, first) }.to change(Revision, :count).by(1)
    expect(page.reload.blocks.first.dig("data", "body")).to eq("Second")
  end

  it "does the same for a collection entry" do
    sign_in_as admin
    collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    entry = collection.entries.create!(slug: "hello", title: "Hello", status: "draft", body_markdown: "One")
    first = entry.versions.newest_first.last
    entry.update!(body_markdown: "Two")

    get collection_entry_versions_path("posts", "hello")
    expect(response).to have_http_status(:success)

    post collection_entry_version_restoration_path("posts", "hello", first)
    expect(entry.reload.body_markdown).to eq("One")
  end

  it "is refused without the write capability" do
    page = make_page
    sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))

    post page_version_restoration_path(page.path, page.versions.first)
    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to match(/permission/)
  end
end
