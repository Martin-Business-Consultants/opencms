# frozen_string_literal: true

require "rails_helper"

RSpec.describe Revision do
  let(:author)    { create(:user) }
  let(:publisher) { create(:user) }

  def make_page(attrs = {})
    Page.create!({
      slug: "p-#{SecureRandom.hex(3)}",
      title: "Original title",
      status: "published",
      locale: "en",
      blocks: [],
      schema: {"fields" => []},
      frontmatter: {},
      seo: {}
    }.merge(attrs))
  end

  describe ".propose!" do
    it "records the change without touching the record" do
      page = make_page
      revision = described_class.propose!(record: page, attributes: {"title" => "New title"}, author: author)

      expect(revision.payload).to eq("title" => "New title")
      expect(page.reload.title).to eq("Original title")
    end

    it "keeps the pre-change values so the diff has something to compare against" do
      page = make_page(title: "Before")
      revision = described_class.propose!(record: page, attributes: {"title" => "After"}, author: author)

      expect(revision.base_snapshot).to eq("title" => "Before")
    end

    it "drops fields that aren't actually changing" do
      page = make_page(title: "Same")
      revision = described_class.propose!(
        record: page,
        attributes: {"title" => "Same", "seo" => {"description" => "new"}},
        author: author
      )

      expect(revision.changed_keys).to eq(["seo"])
    end

    it "refuses status — publishing is the publish capability's job" do
      page = make_page(status: "published")
      revision = described_class.propose!(
        record: page,
        attributes: {"status" => "draft", "title" => "New"},
        author: author
      )

      expect(revision.changed_keys).to eq(["title"])
    end

    it "is invalid with nothing to review" do
      page = make_page(title: "Same")
      expect {
        described_class.propose!(record: page, attributes: {"title" => "Same"}, author: author)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "rejects a second pending revision for the same record" do
      page = make_page
      described_class.propose!(record: page, attributes: {"title" => "One"}, author: author)

      expect {
        described_class.propose!(record: page, attributes: {"title" => "Two"}, author: author)
      }.to raise_error(ActiveRecord::RecordInvalid, /already pending/)
    end
  end

  describe "#apply!" do
    it "writes the payload and stamps the decision" do
      page = make_page(title: "Before")
      revision = described_class.propose!(record: page, attributes: {"title" => "After"}, author: author)

      expect(revision.apply!(by: publisher, comment: "looks right")).to be(true)
      expect(page.reload.title).to eq("After")
      expect(revision.reload).to have_attributes(
        state: "applied", decided_by: publisher, decision_comment: "looks right"
      )
      expect(revision.decided_at).to be_present
    end

    it "leaves publication state alone" do
      page = make_page(status: "published")
      described_class.propose!(record: page, attributes: {"title" => "After"}, author: author)
        .apply!(by: publisher)

      expect(page.reload.status).to eq("published")
    end

    it "won't apply twice" do
      page = make_page
      revision = described_class.propose!(record: page, attributes: {"title" => "After"}, author: author)
      revision.apply!(by: publisher)

      expect(revision.apply!(by: publisher)).to be(false)
    end
  end

  describe "#reject!" do
    it "resolves without touching the record" do
      page = make_page(title: "Before")
      revision = described_class.propose!(record: page, attributes: {"title" => "After"}, author: author)

      expect(revision.reject!(by: publisher, comment: "no")).to be(true)
      expect(page.reload.title).to eq("Before")
      expect(revision.reload.state).to eq("rejected")
    end

    it "frees the record for a new proposal" do
      page = make_page
      described_class.propose!(record: page, attributes: {"title" => "One"}, author: author)
        .reject!(by: publisher)

      expect {
        described_class.propose!(record: page, attributes: {"title" => "Two"}, author: author)
      }.not_to raise_error
    end
  end

  describe "#stale?" do
    it "is false while nothing else touches the record" do
      page = make_page
      revision = described_class.propose!(record: page, attributes: {"title" => "After"}, author: author)

      expect(revision).not_to be_stale
    end

    it "notices an edit that landed underneath, and names the field" do
      page = make_page(title: "Before")
      revision = described_class.propose!(record: page, attributes: {"title" => "After"}, author: author)

      page.update!(title: "Somebody else's title")

      expect(revision.reload).to be_stale
      expect(revision.drifted_keys).to eq(["title"])
    end
  end
end
