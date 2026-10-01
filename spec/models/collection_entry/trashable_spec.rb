# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry::Trashable do
  let(:collection) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }

  def make(slug) = collection.entries.create!(slug: slug, title: slug.titleize, status: "draft")

  it "trashes an entry, recording it as it was" do
    entry = make("hello")

    entry.trash

    expect(CollectionEntry.with_discarded.find(entry.id)).to be_discarded
    expect(AuditLog.last).to have_attributes(action: "entry.deleted", target_type: "CollectionEntry", target_id: entry.id,
      metadata: {"collection" => "posts", "slug" => "hello", "status" => "draft"})
  end

  it "purges an entry for good" do
    entry = make("hello")

    entry.purge

    expect(CollectionEntry.with_discarded.exists?(entry.id)).to be(false)
    expect(AuditLog.last).to have_attributes(action: "entry.purged", metadata: {"collection" => "posts", "slug" => "hello"})
  end

  it "trashes a set under one event naming the ones found" do
    CollectionEntry.trash_all([make("a"), make("b")], collection: collection)

    expect(collection.entries.count).to eq(0)
    expect(AuditLog.last).to have_attributes(action: "entry.bulk_deleted", target: nil,
      metadata: {"collection" => "posts", "count" => 2, "slugs" => %w[a b]})
  end
end
