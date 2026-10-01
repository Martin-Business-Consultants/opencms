# frozen_string_literal: true

require "rails_helper"

# Deciding a review request, or a revision, records the decision itself —
# the admin and the API both call these verbs.
RSpec.describe "Review decisions" do
  let(:author) { create(:user) }
  let(:reviewer) { create(:user) }
  let(:page) { Page.create!(slug: "about", title: "About", status: "draft", locale: "en") }

  def open_request = page.review_requests.create!(requested_by: author)

  it "approves, publishes and records it once" do
    review = open_request

    expect(review.approve!(by: reviewer, comment: "ok")).to be(true)
    expect(page.reload.status).to eq("published")
    expect(AuditLog.where(action: "review_request.approved").count).to eq(1)
    expect(review.approve!(by: reviewer)).to be(false)
  end

  it "records a change request and a cancellation" do
    open_request.request_changes!(by: reviewer, comment: "more")
    expect(AuditLog.last.action).to eq("review_request.changes_requested")

    expect(open_request.cancel!(by: reviewer)).to be(false)
    open_request_cancelled = ReviewRequest.pending.last
    open_request_cancelled.cancel!(by: author)
    expect(AuditLog.last.action).to eq("review_request.cancelled")
  end

  it "records a proposal, and an applied or rejected revision with what it changed" do
    page.update!(status: "published")
    revision = Revision.propose(record: page, attributes: {title: "About us"}, author: author, source: "ui")
    expect(AuditLog.last).to have_attributes(action: "revision.proposed", metadata: include("fields" => ["title"]))

    revision.apply!(by: reviewer, forced: true)
    expect(page.reload.title).to eq("About us")
    expect(AuditLog.last).to have_attributes(action: "revision.applied", metadata: include("forced" => true, "fields" => ["title"]))

    other = Revision.propose(record: page, attributes: {title: "Again"}, author: author)
    other.reject!(by: reviewer)
    expect(AuditLog.last).to have_attributes(action: "revision.rejected", metadata: {"fields" => ["title"]})
  end
end
