# frozen_string_literal: true

require "rails_helper"

# Bulk status changes used to go through update_all, which skips callbacks:
# no content webhook, no deploy hook. They now save record by record, so a
# bulk publish announces itself exactly as N single publishes would.
RSpec.describe "Bulk status changes fire content webhooks", type: :request do
  let(:admin) { create(:user) }
  let(:api_headers) { {"Authorization" => "Bearer #{admin.api_token.token}"} }

  before do
    Webhook.create!(name: "any", url: "https://example.com/in",
                    events: %w[page.published page.unpublished page.updated entry.published entry.unpublished entry.updated])
    Setting.set("deploy", {"url" => "https://hooks.example.com/build"})
  end

  def make_page(slug, status: "draft")
    Page.create!(slug: slug, title: slug.titleize, status: status, locale: "en")
  end

  def make_entry(collection, slug, status: "draft")
    CollectionEntry.create!(collection: collection, slug: slug, title: slug.titleize, status: status,
                            locale: "en", frontmatter: {}, body_markdown: "")
  end

  def webhook_events
    enqueued_jobs.select { |j| j["job_class"] == "Webhook::DeliveryJob" }.map { |j| j["arguments"][1] }
  end

  def deploy_jobs
    enqueued_jobs.select { |j| j["job_class"] == "Deploys::TriggerJob" }
  end

  # Runs every scheduled deploy job and counts the build-hook POSTs that
  # actually go out. The debounce means only the last-scheduled one fires.
  def deploy_hook_posts
    posts = 0
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil)
    allow(http).to receive(:request) { posts += 1; Net::HTTPOK.new("1.1", "200", "OK") }
    allow(Net::HTTP).to receive(:new).and_return(http)

    deploy_jobs.each { |j| Deploys::TriggerJob.perform_now(*j["arguments"]) }
    posts
  end

  describe "POST /api/pages/bulk_update_status" do
    it "fires page.published per page and debounces the deploy hook to one build" do
      make_page("about")
      make_page("pricing")
      clear_enqueued_jobs

      post "/api/pages/bulk_update_status",
        params: {status: "published", paths: %w[about pricing]}, headers: api_headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body["updated"]).to eq(2)
      expect(webhook_events).to eq(%w[page.published page.published])
      expect(deploy_jobs.size).to eq(2)
      expect(deploy_hook_posts).to eq(1)
    end

    it "fires page.unpublished when leaving published" do
      make_page("about", status: "published")
      clear_enqueued_jobs

      post "/api/pages/bulk_update_status",
        params: {status: "draft", paths: %w[about]}, headers: api_headers, as: :json

      expect(webhook_events).to eq(%w[page.unpublished])
    end

    it "leaves pages already at the target status alone" do
      make_page("about", status: "published")
      clear_enqueued_jobs

      post "/api/pages/bulk_update_status",
        params: {status: "published", paths: %w[about]}, headers: api_headers, as: :json

      expect(response.parsed_body["updated"]).to eq(1)
      expect(webhook_events).to be_empty
      expect(deploy_jobs).to be_empty
    end

    it "rolls the whole batch back when one page fails validation" do
      make_page("about")
      broken = make_page("broken")
      broken.update_columns(schema: {"fields" => [{"name" => "hero", "label" => "Hero", "type" => "string", "required" => true}]})
      clear_enqueued_jobs

      post "/api/pages/bulk_update_status",
        params: {status: "published", paths: %w[about broken]}, headers: api_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Page.where(status: "published")).to be_empty
      expect(webhook_events).to be_empty
    end
  end

  describe "POST /api/collections/:slug/entries/bulk_update_status" do
    let(:collection) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }

    it "fires entry.published per entry and debounces the deploy hook to one build" do
      make_entry(collection, "one")
      make_entry(collection, "two")
      clear_enqueued_jobs

      post "/api/collections/posts/entries/bulk_update_status",
        params: {status: "published", slugs: %w[one two]}, headers: api_headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body["updated"]).to eq(2)
      expect(webhook_events).to eq(%w[entry.published entry.published])
      expect(deploy_hook_posts).to eq(1)
    end

    it "fires entry.unpublished when leaving published" do
      make_entry(collection, "one", status: "published")
      clear_enqueued_jobs

      post "/api/collections/posts/entries/bulk_update_status",
        params: {status: "archived", slugs: %w[one]}, headers: api_headers, as: :json

      expect(webhook_events).to eq(%w[entry.unpublished])
    end
  end

  describe "admin bulk status" do
    before { sign_in_as admin }

    it "fires page.published for the pages screen's bulk publish" do
      make_page("about")
      clear_enqueued_jobs

      post pages_bulk_status_changes_path, params: {status: "published", slugs: %w[about]}

      expect(Page.find_by!(slug: "about").status).to eq("published")
      expect(webhook_events).to eq(%w[page.published])
    end

    it "fires entry.published for the entries screen's bulk publish" do
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
      make_entry(collection, "one")
      clear_enqueued_jobs

      post collection_entries_bulk_status_changes_path("posts"), params: {status: "published", slugs: %w[one]}

      expect(collection.entries.find_by!(slug: "one").status).to eq("published")
      expect(webhook_events).to eq(%w[entry.published])
    end
  end
end
