# frozen_string_literal: true

require "rails_helper"

# Publishing a draft needs the publish capability, in the admin and the API
# alike (PublicationGate). Without it the draft still saves; the status or
# schedule that would have published it is held back, and a review request
# asks for it. Approving the request publishes.
RSpec.describe "Publishing needs the publish capability", type: :request do
  before { Session.delete_all }

  let(:writer) do
    create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write entries:read entries:write collections:read]))
  end
  let(:publisher) { create(:user) }
  let!(:collection) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }

  def api(user) = {"Authorization" => "Bearer #{user.api_token.token}"}

  def json = JSON.parse(response.body)

  describe "over the API" do
    it "saves the draft, holds back the publish, and asks for review" do
      page = Page.create!(slug: "notes", title: "Notes", status: "draft")

      patch "/api/pages/notes", params: {page: {title: "Better notes", status: "published"}}, headers: api(writer), as: :json

      expect(response).to have_http_status(:accepted)
      expect(json).to include("status" => "pending_review", "ignored_fields" => ["status"])
      expect(json.dig("record", "status")).to eq("draft")
      expect(page.reload).to have_attributes(title: "Better notes", status: "draft")
      expect(ReviewRequest.pending.for_reviewable(page).first.requested_by).to eq(writer)
    end

    it "creates a record asked for published as a draft, waiting for review" do
      post "/api/collections/posts/entries", params: {entry: {slug: "hello", title: "Hello", status: "published", locale: "en"}},
        headers: api(writer), as: :json

      expect(response).to have_http_status(:accepted)
      entry = collection.entries.find_by!(slug: "hello")
      expect(entry.status).to eq("draft")
      expect(ReviewRequest.pending.for_reviewable(entry)).to exist
    end

    it "reuses the open request rather than filing another" do
      Page.create!(slug: "notes", title: "Notes", status: "draft")

      2.times { patch "/api/pages/notes", params: {page: {status: "published"}}, headers: api(writer), as: :json }

      expect(ReviewRequest.pending.count).to eq(1)
    end

    it "leaves a publisher's publish alone" do
      page = Page.create!(slug: "notes", title: "Notes", status: "draft")

      patch "/api/pages/notes", params: {page: {status: "published"}}, headers: api(publisher), as: :json

      expect(response).to have_http_status(:ok)
      expect(page.reload.status).to eq("published")
      expect(ReviewRequest.count).to eq(0)
    end

    it "keeps a writer's plain draft edit as it was" do
      page = Page.create!(slug: "notes", title: "Notes", status: "draft")

      patch "/api/pages/notes", params: {page: {title: "Renamed"}}, headers: api(writer), as: :json

      expect(response).to have_http_status(:ok)
      expect(page.reload.title).to eq("Renamed")
      expect(ReviewRequest.count).to eq(0)
    end

    it "refuses a publish from a service token, which has no one to ask for review, before saving anything" do
      page = Page.create!(slug: "notes", title: "Notes", status: "draft")
      token = ServiceToken.issue!(name: "Script", role: create(:role, permissions: %w[pages:read pages:write])).token

      patch "/api/pages/notes", params: {page: {title: "Renamed", status: "published"}},
        headers: {"Authorization" => "Bearer #{token}"}, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json).to include("capability" => "pages:publish")
      expect(page.reload).to have_attributes(title: "Notes", status: "draft")
    end
  end

  describe "in the admin" do
    it "offers Submit for review on a draft, saves it, and asks for review" do
      page = Page.create!(slug: "notes", title: "Notes", status: "draft")
      sign_in_as writer

      get edit_page_path("notes")
      expect(response.body).to include("Submit for review", "Save Draft")

      patch page_path("notes"), params: {page: {title: "Better notes", status: "published"}}

      expect(response).to redirect_to(edit_page_path("notes"))
      expect(flash[:notice]).to eq("Saved as a draft. Publishing it is waiting for review.")
      expect(page.reload).to have_attributes(title: "Better notes", status: "draft")
      expect(ReviewRequest.pending.for_reviewable(page)).to exist

      get edit_page_path("notes")
      expect(response.body).to include("Waiting for review since")
    end

    it "holds back a schedule too" do
      page = Page.create!(slug: "notes", title: "Notes", status: "draft")
      sign_in_as writer

      patch page_path("notes"), params: {page: {publish_at: 2.days.from_now.iso8601}}

      expect(page.reload.publish_at).to be_nil
      expect(ReviewRequest.pending.for_reviewable(page)).to exist
    end

    it "creates an entry asked for published as a draft" do
      sign_in_as writer

      post collection_entries_path("posts"), params: {entry: {title: "Hello", slug: "hello", status: "published"}}

      entry = collection.entries.find_by!(slug: "hello")
      expect(entry.status).to eq("draft")
      expect(flash[:notice]).to include("Publishing it is waiting for review")
    end

    it "publishes once a reviewer approves" do
      page = Page.create!(slug: "notes", title: "Notes", status: "draft")
      request = ReviewRequest.request_publication(page, by: writer)

      request.approve!(by: publisher)

      expect(page.reload.status).to eq("published")
    end
  end
end
