# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReviewRequest do
  let(:author)    { create(:user) }
  let(:publisher) { create(:user) }

  def make_page(attrs = {})
    Page.create!({
      slug:        "p-#{SecureRandom.hex(3)}",
      title:       "T",
      status:      "draft",
      locale:      "en",
      blocks:      [],
      schema:      {"fields" => []},
      frontmatter: {},
      seo:         {}
    }.merge(attrs))
  end

  it "rejects a second pending request for the same record" do
    page = make_page
    described_class.create!(reviewable: page, requested_by: author)
    second = described_class.new(reviewable: page, requested_by: author)
    expect(second).not_to be_valid
  end

  it "allows a new request after a previous one is decided" do
    page = make_page
    first = described_class.create!(reviewable: page, requested_by: author)
    first.cancel!(by: author)

    second = described_class.create(reviewable: page, requested_by: author)
    expect(second).to be_valid
  end

  describe "#approve!" do
    it "publishes the underlying record and stamps the decision" do
      page = make_page(status: "draft")
      r = described_class.create!(reviewable: page, requested_by: author)

      expect(r.approve!(by: publisher, comment: "lgtm")).to eq(true)
      expect(page.reload.status).to eq("published")
      expect(r.reload.state).to eq("approved")
      expect(r.reviewer_id).to eq(publisher.id)
      expect(r.decision_comment).to eq("lgtm")
    end

    it "is a no-op once decided" do
      page = make_page
      r = described_class.create!(reviewable: page, requested_by: author)
      r.approve!(by: publisher)
      expect(r.approve!(by: publisher)).to eq(false)
    end
  end

  describe "#request_changes!" do
    it "doesn't publish but records the decision" do
      page = make_page(status: "draft")
      r = described_class.create!(reviewable: page, requested_by: author)

      expect(r.request_changes!(by: publisher, comment: "fix the title")).to eq(true)
      expect(page.reload.status).to eq("draft")
      expect(r.reload.state).to eq("changes_requested")
    end
  end

  describe "#cancel!" do
    it "only allows the original author to cancel" do
      page = make_page
      r = described_class.create!(reviewable: page, requested_by: author)
      expect(r.cancel!(by: publisher)).to eq(false)
      expect(r.reload.state).to eq("pending")

      expect(r.cancel!(by: author)).to eq(true)
      expect(r.reload.state).to eq("cancelled")
    end
  end
end
