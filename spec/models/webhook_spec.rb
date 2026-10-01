# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhook do
  def make(attrs = {})
    described_class.new({
      name:   "n",
      url:    "https://example.com/hook",
      events: ["page.published"]
    }.merge(attrs))
  end

  describe "validations" do
    it "requires name, url, events" do
      w = described_class.new
      expect(w).not_to be_valid
      expect(w.errors[:name]).to be_present
      expect(w.errors[:url]).to be_present
      expect(w.errors[:events]).to be_present
    end

    it "rejects non-http(s) URLs" do
      expect(make(url: "ftp://example.com")).not_to be_valid
    end

    it "rejects unknown event names" do
      w = make(events: ["page.published", "bogus.event"])
      expect(w).not_to be_valid
      expect(w.errors[:events].join).to match(/bogus\.event/)
    end

    it "requires at least one event" do
      expect(make(events: [])).not_to be_valid
    end

    it "rejects non-hash headers" do
      w = make
      w.headers = "not-a-hash"
      expect(w).not_to be_valid
    end
  end

  describe "secret generation" do
    it "generates a secret on create" do
      w = make
      w.save!
      expect(w.secret).to start_with("whsec_")
    end

    it "rotates the secret" do
      w = make
      w.save!
      old = w.secret
      w.regenerate_secret!
      expect(w.secret).not_to eq(old)
    end
  end

  describe ".for_event" do
    it "filters to webhooks subscribed to the given event" do
      a = make(events: ["page.updated"]); a.save!
      _b = make(events: ["page.published"]); _b.save!
      _c = make(events: ["entry.published"]); _c.save!

      expect(described_class.for_event("page.updated").pluck(:id)).to contain_exactly(a.id)
    end

    it "skips inactive webhooks" do
      a = make(events: ["page.published"]); a.save!
      b = make(events: ["page.published"], active: false); b.save!

      expect(described_class.for_event("page.published").pluck(:id)).to contain_exactly(a.id)
    end
  end
end
