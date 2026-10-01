# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::Publishable do
  include ActiveSupport::Testing::TimeHelpers

  def make(slug, **attrs) = Page.create!({slug: slug, title: slug.titleize, status: "draft", locale: "en"}.merge(attrs))

  describe "the schedule" do
    it "publishes pages whose publish_at has passed, keeping an earlier published_at" do
      travel_to Time.utc(2026, 9, 1, 12) do
        due = make("due", publish_at: 1.minute.ago)
        later = make("later", publish_at: 1.hour.from_now)

        Page.publish_due

        expect(due.reload).to have_attributes(status: "published", publish_at: nil, published_at: Time.current)
        expect(later.reload.status).to eq("draft")
      end
    end

    it "archives pages whose unpublish_at has passed" do
      travel_to Time.utc(2026, 9, 1, 12) do
        page = make("gone", status: "published", published_at: 1.day.ago, unpublish_at: 1.minute.ago)

        Page.unpublish_due

        expect(page.reload).to have_attributes(status: "archived", unpublish_at: nil)
      end
    end

    it "says whether a change is still to come" do
      expect(make("soon", publish_at: 1.hour.from_now)).to be_scheduled
      expect(make("now", publish_at: 1.hour.ago)).not_to be_scheduled
    end
  end

  describe ".change_status_of" do
    it "saves each page that isn't already there, and records one event" do
      a = make("a")
      b = make("b", status: "published", published_at: Time.current)

      expect { Page.change_status_of([a, b], to: "published") }.to change(AuditLog, :count).by(1)

      expect(a.reload.status).to eq("published")
      expect(AuditLog.last).to have_attributes(action: "page.bulk_status_changed",
        metadata: {"to" => "published", "count" => 2, "paths" => %w[a b]})
    end

    it "names the pages it changed, not the ones it was asked for" do
      pages = Page.where(path: %w[a missing]).to_a.presence || [make("a")]
      Page.change_status_of(pages, to: "archived")

      expect(AuditLog.last.metadata["paths"]).to eq(%w[a])
    end

    it "changes nothing when one page fails validation" do
      good = make("good")
      bad = make("bad")
      bad.update_column(:title, "")

      expect { Page.change_status_of([good, bad], to: "published") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(good.reload.status).to eq("draft")
    end

    it "records nothing for no pages" do
      expect { Page.change_status_of([], to: "published") }.not_to change(AuditLog, :count)
    end
  end

  describe "#track_update" do
    let(:page) { make("about") }

    it "names the event after what the save did to the status" do
      page.track_update(from: "draft")
      page.update!(status: "published")
      page.track_update(from: "draft")
      page.update!(status: "archived")
      page.track_update(from: "published")
      page.update!(status: "draft")
      page.track_update(from: "archived")

      expect(AuditLog.order(:id).last(4).map { [it.action, it.metadata] }).to eq([
        ["page.updated", {"path" => "about", "status" => "draft"}],
        ["page.published", {"path" => "about", "from" => "draft"}],
        ["page.unpublished", {"path" => "about", "to" => "archived"}],
        ["page.updated", {"path" => "about", "from" => "archived", "to" => "draft"}]
      ])
    end
  end
end
