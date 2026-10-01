# frozen_string_literal: true

require "rails_helper"

# The gate: an API client that can't publish doesn't get to change live
# content. Its writes become revisions; a publisher's writes still apply.
#
# Sets the site up as a new install would; every example works on
# freshly-slugged records.
RSpec.describe "API write gate", type: :request do
  GATE_SUBDOMAIN = "writegate"


  before do
    SiteSetup.new(
      name: "Write Gate Spec",
      owner_email: "owner@#{GATE_SUBDOMAIN}.example.com"
    ).call
  end

  # A token carries exactly its owner's role, so "a token that can't publish"
  # is a user whose role holds write but not publish.
  def token_for(name, capabilities)
    role = Role.find_or_create_by!(name: name) { |r| r.permissions = capabilities }
    role.update!(permissions: capabilities)

    user = User.find_or_create_by!(email: "#{name.parameterize}@#{GATE_SUBDOMAIN}.example.com") do |u|
      u.name = name
      u.password = "password1234"
      u.password_confirmation = "password1234"
      u.verified = true
    end
    user.update!(role: role)

    {"Authorization" => "Bearer #{ApiToken.for(user).rotate!}"}
  end

  def writer
    @writer ||= token_for("Gate writer",
      %w[pages:read pages:write entries:read entries:write globals:read globals:write])
  end

  def publisher
    @publisher ||= token_for("Gate publisher", %w[pages:read pages:write pages:publish])
  end

  def make_page(attrs = {})
    Page.create!({
      slug: "p-#{SecureRandom.hex(4)}",
      title: "Live title",
      status: "published",
      locale: "en",
      blocks: [],
      schema: {"fields" => []},
      frontmatter: {},
      seo: {}
    }.merge(attrs))
  end

  def pending_revisions = Revision.pending.to_a

  def body = JSON.parse(response.body)

  describe "a client without publish, editing a published page" do
    it "files a revision instead of writing" do
      page = make_page(title: "Live title")

      patch "/api/pages/#{page.path}", params: {page: {title: "Proposed title"}}, headers: writer, as: :json

      expect(response).to have_http_status(:accepted)
      expect(body["status"]).to eq("pending_review")
      expect(body["revision"]["fields"]).to eq(["title"])
      expect(body["review_url"]).to be_present

      expect(page.reload.title).to eq("Live title")
      expect(pending_revisions.map(&:revisable_id)).to include(page.id)
    end

    it "won't let a status change ride along" do
      page = make_page(status: "published")

      patch "/api/pages/#{page.path}",
        params: {page: {title: "Proposed", status: "draft"}}, headers: writer, as: :json

      expect(response).to have_http_status(:accepted)
      expect(body["ignored_fields"]).to include("status")
      expect(page.reload.status).to eq("published")
    end

    it "refuses a status-only change rather than quietly applying it" do
      page = make_page(status: "published")

      patch "/api/pages/#{page.path}", params: {page: {status: "draft"}}, headers: writer, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["status"]).to eq("unchanged")
      expect(page.reload.status).to eq("published")
    end

    it "409s a second proposal and points at the open one" do
      page = make_page

      patch "/api/pages/#{page.path}", params: {page: {title: "One"}}, headers: writer, as: :json
      expect(response).to have_http_status(:accepted)
      first_id = body["revision"]["id"]

      patch "/api/pages/#{page.path}", params: {page: {title: "Two"}}, headers: writer, as: :json

      expect(response).to have_http_status(:conflict)
      expect(body["error"]).to eq("revision_pending")
      expect(body["revision"]["id"]).to eq(first_id)
    end
  end

  describe "a draft page" do
    it "is written directly — nobody is looking at it yet" do
      page = make_page(status: "draft", title: "Draft title")

      patch "/api/pages/#{page.path}", params: {page: {title: "Edited"}}, headers: writer, as: :json

      expect(response).to have_http_status(:success)
      expect(page.reload.title).to eq("Edited")
      expect(pending_revisions.map(&:revisable_id)).not_to include(page.id)
    end
  end

  describe "a client with publish" do
    it "writes live content directly" do
      page = make_page(title: "Live title")

      patch "/api/pages/#{page.path}", params: {page: {title: "Edited"}}, headers: publisher, as: :json

      expect(response).to have_http_status(:success)
      expect(page.reload.title).to eq("Edited")
      expect(pending_revisions.map(&:revisable_id)).not_to include(page.id)
    end
  end

  describe "collection entries" do
    it "gates a published entry" do
      entry = begin
        collection = Collection.find_or_create_by!(slug: "posts") do |c|
          c.name = "Posts"
          c.schema = {"fields" => []}
        end
        collection.entries.create!(
          slug: "e-#{SecureRandom.hex(4)}", title: "Live", status: "published",
          locale: "en", body_markdown: "before", frontmatter: {}, seo: {}
        )
      end

      patch "/api/collections/posts/entries/#{entry.slug}",
        params: {entry: {body_markdown: "after"}}, headers: writer, as: :json

      expect(response).to have_http_status(:accepted)
      expect(entry.reload.body_markdown).to eq("before")
    end
  end

  describe "globals" do
    it "gates them unconditionally — they have no draft state" do
      slug = "nav_#{SecureRandom.hex(3)}"
      global = Global.create!(slug: slug, name: "Navigation", data: {"items" => []})

      patch "/api/globals/#{slug}",
        params: {global: {data: {"items" => [{"label" => "Home"}]}}}, headers: writer, as: :json

      expect(response).to have_http_status(:accepted)
      expect(global.reload.data).to eq("items" => [])
    end
  end
end
