# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::Trashable do
  def make(slug) = Page.create!(slug: slug, title: slug.titleize, status: "draft", locale: "en")

  it "trashes a page, recording it as it was" do
    page = make("about")

    page.trash

    expect(Page.with_discarded.find(page.id)).to be_discarded
    # The row's target is the trashed page, which default-scoped reads hide.
    expect(AuditLog.last).to have_attributes(action: "page.deleted", target_type: "Page", target_id: page.id,
      metadata: {"path" => "about", "status" => "draft"})
  end

  it "purges a page for good" do
    page = make("about")

    page.purge

    expect(Page.with_discarded.exists?(page.id)).to be(false)
    expect(AuditLog.last).to have_attributes(action: "page.purged", metadata: {"path" => "about"})
  end

  it "trashes a set of pages under one event" do
    pages = [make("a"), make("b")]

    Page.trash_all(pages)

    expect(Page.count).to eq(0)
    expect(AuditLog.last).to have_attributes(action: "page.bulk_deleted", target: nil,
      metadata: {"count" => 2, "paths" => %w[a b]})
  end
end
