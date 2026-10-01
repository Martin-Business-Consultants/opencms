# frozen_string_literal: true

require "rails_helper"

RSpec.describe Collection::Removable do
  def make(slug) = Collection.create!(slug: slug, name: slug.titleize, schema: {"fields" => []})

  it "deletes a collection and its entries, recording it first" do
    collection = make("posts")
    collection.entries.create!(slug: "a", title: "A", status: "draft")

    collection.remove

    expect(Collection.exists?(collection.id)).to be(false)
    expect(CollectionEntry.with_discarded.count).to eq(0)
    expect(AuditLog.last).to have_attributes(action: "collection.deleted", metadata: {"slug" => "posts"})
  end

  it "deletes a set under one event naming the ones found" do
    Collection.remove_all([make("a"), make("b")])

    expect(Collection.count).to eq(0)
    expect(AuditLog.last).to have_attributes(action: "collection.bulk_deleted", target: nil,
      metadata: {"count" => 2, "slugs" => %w[a b]})
  end

  it "records nothing for an empty set" do
    expect { Collection.remove_all([]) }.not_to change(AuditLog, :count)
  end
end
