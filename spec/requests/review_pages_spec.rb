# frozen_string_literal: true

require "rails_helper"

# The pages behind the review queue, rendered with real data: a revision's
# diff, a pending review request, a webhook's settings and delivery log.
RSpec.describe "Review and settings pages", type: :request do
  let(:admin) { create(:user) }
  let(:author) { create(:user) }
  let(:page_record) do
    Page.create!(title: "Pricing", slug: "pricing", status: "published", locale: "en",
                 blocks: [{"id" => "b1", "type" => "hero", "data" => {"heading" => "Old"}}], seo: {"meta_title" => "Old"})
  end

  before do
    BlockType.create!(slug: "hero", label: "Hero", fields: [{"name" => "heading", "type" => "text", "label" => "Heading"}])
    sign_in_as admin
  end

  it "shows a revision's diff and decides it" do
    revision = Revision.propose!(record: page_record, author: author, attributes: {
      title: "Plans", seo: {"meta_title" => "New"},
      blocks: [{"id" => "b1", "type" => "hero", "data" => {"heading" => "New"}}]
    })

    get revision_path(revision)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Pricing", "Plans", "meta_title", "Approve and apply", "Reject")

    post revision_approval_path(revision), params: {comment: "ok"}
    expect(response).to redirect_to(revisions_path)
    expect(page_record.reload.title).to eq("Plans")
    expect(revision.reload.state).to eq("applied")
  end

  it "rejects a revision without touching the record" do
    revision = Revision.propose!(record: page_record, author: author, attributes: {title: "Plans"})

    post revision_rejection_path(revision)

    expect(revision.reload.state).to eq("rejected")
    expect(page_record.reload.title).to eq("Pricing")
  end

  it "lists a pending review request and approves it" do
    draft = Page.create!(title: "Team", slug: "team", status: "draft", locale: "en")
    request = ReviewRequest.create!(reviewable: draft, requested_by: author, state: "pending", comment: "Ready")

    get review_requests_path
    expect(response.body).to include("Team", "“Ready”", "Approve &amp; publish")

    post review_request_approval_path(request)
    expect(request.reload.state).to eq("approved")
    expect(draft.reload.status).to eq("published")
  end

  it "requests changes on a review request" do
    draft = Page.create!(title: "Team", slug: "team", status: "draft", locale: "en")
    request = ReviewRequest.create!(reviewable: draft, requested_by: author, state: "pending")

    post review_request_change_request_path(request), params: {comment: "Shorter"}

    expect(request.reload.state).to eq("changes_requested")
  end

  it "renders a webhook's edit and show pages with deliveries" do
    webhook = Webhook.create!(name: "Astro", url: "https://e.test/hook", events: ["page.published"], headers: {"X-A" => "1"})
    webhook.deliveries.create!(event: "page.published", payload: "{}", success: false, response_status: 500, duration_ms: 12, error: "boom")

    get edit_webhook_path(webhook)
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Signing secret", "X-A: 1", "boom", "Send a test")

    get webhook_path(webhook)
    expect(response).to have_http_status(:success)
    expect(response.body).to include("https://e.test/hook", "boom")
  end
end
