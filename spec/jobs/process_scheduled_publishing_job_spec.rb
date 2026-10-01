# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessScheduledPublishingJob do
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

  def make_collection
    Collection.create!(slug: "blog-#{SecureRandom.hex(3)}", name: "Blog", schema: {"fields" => []})
  end

  def make_entry(coll, attrs = {})
    CollectionEntry.create!({
      collection:    coll,
      slug:          "e-#{SecureRandom.hex(3)}",
      title:         "E",
      status:        "draft",
      locale:        "en",
      frontmatter:   {},
      body_markdown: "",
      seo:           {}
    }.merge(attrs))
  end

  describe "publishing" do
    it "flips draft pages whose publish_at has passed to published" do
      now = Time.current
      page = make_page(status: "draft", publish_at: 1.minute.ago)

      described_class.new.perform(now: now)

      page.reload
      expect(page.status).to eq("published")
      expect(page.publish_at).to be_nil
      expect(page.published_at).to be_within(2.seconds).of(now)
    end

    it "does not touch pages whose publish_at is in the future" do
      page = make_page(status: "draft", publish_at: 1.hour.from_now)
      described_class.new.perform(now: Time.current)
      expect(page.reload.status).to eq("draft")
    end

    it "is a no-op for pages already published" do
      page = make_page(status: "published", publish_at: 1.minute.ago, published_at: 2.days.ago)
      original_published_at = page.published_at

      described_class.new.perform(now: Time.current)

      page.reload
      expect(page.status).to eq("published")
      # publish_at not cleared (the scope skips already-published rows)
      expect(page.publish_at).to be_present
      expect(page.published_at).to be_within(1.second).of(original_published_at)
    end

    it "publishes collection entries the same way" do
      coll  = make_collection
      entry = make_entry(coll, status: "draft", publish_at: 1.minute.ago)

      described_class.new.perform(now: Time.current)

      expect(entry.reload.status).to eq("published")
    end
  end

  describe "unpublishing" do
    it "archives published pages whose unpublish_at has passed" do
      page = make_page(status: "published", unpublish_at: 1.minute.ago)

      described_class.new.perform(now: Time.current)

      page.reload
      expect(page.status).to eq("archived")
      expect(page.unpublish_at).to be_nil
    end

    it "leaves drafts alone" do
      page = make_page(status: "draft", unpublish_at: 1.minute.ago)
      described_class.new.perform(now: Time.current)
      expect(page.reload.status).to eq("draft")
    end
  end

  describe "validations" do
    it "rejects unpublish_at before publish_at" do
      page = Page.new(
        slug:        "x",
        title:       "T",
        status:      "draft",
        locale:      "en",
        blocks:      [],
        schema:      {"fields" => []},
        frontmatter: {},
        seo:         {},
        publish_at:  1.day.from_now,
        unpublish_at: 1.hour.from_now
      )
      expect(page).not_to be_valid
      expect(page.errors[:unpublish_at].join).to match(/after/)
    end
  end
end
