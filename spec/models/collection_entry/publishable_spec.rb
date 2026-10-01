# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry::Publishable do
  let(:collection) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }

  def make(slug, **attrs) = collection.entries.create!({slug: slug, title: slug.titleize, status: "draft"}.merge(attrs))

  it "publishes and unpublishes on schedule" do
    due = make("due", publish_at: 1.minute.ago)
    ending = make("ending", status: "published", unpublish_at: 1.minute.ago)
    later = make("later", publish_at: 1.hour.from_now)

    CollectionEntry.publish_due
    CollectionEntry.unpublish_due

    expect(due.reload).to have_attributes(status: "published", publish_at: nil)
    expect(ending.reload).to have_attributes(status: "archived", unpublish_at: nil)
    expect(later.reload.status).to eq("draft")
    expect(later).to be_scheduled
  end

  it "changes the status of a set in one go, recording the ones found" do
    entries = [make("a"), make("b", status: "published")]

    CollectionEntry.change_status_of(entries, to: "published", collection: collection)

    expect(collection.entries.pluck(:status)).to all(eq("published"))
    expect(AuditLog.last).to have_attributes(action: "entry.bulk_status_changed",
      metadata: {"collection" => "posts", "to" => "published", "count" => 2, "slugs" => %w[a b]})
  end

  it "changes nothing when one entry can't be saved" do
    good = make("good")
    bad = make("bad")
    bad.title = ""

    expect { CollectionEntry.change_status_of([good, bad], to: "published", collection: collection) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(good.reload.status).to eq("draft")
  end

  it "says what an edit did to the status" do
    entry = make("hello")

    entry.track_creation
    expect(AuditLog.last).to have_attributes(action: "entry.created", metadata: {"collection" => "posts", "slug" => "hello", "status" => "draft"})

    entry.update!(status: "published")
    entry.track_update(from: "draft")
    expect(AuditLog.last).to have_attributes(action: "entry.published", metadata: {"collection" => "posts", "slug" => "hello", "from" => "draft"})

    entry.update!(status: "archived")
    entry.track_update(from: "published")
    expect(AuditLog.last).to have_attributes(action: "entry.unpublished", metadata: {"collection" => "posts", "slug" => "hello", "to" => "archived"})
  end
end
