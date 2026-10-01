# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trash do
  def page(slug) = Page.create!(slug: slug, title: slug.titleize, status: "draft", locale: "en")

  it "finds a trashed record by the kind a route names, and refuses kinds it doesn't know" do
    record = page("gone").tap(&:discard!)

    expect(described_class.find("page", record.id)).to eq(record)
    expect { described_class.find("nope", record.id) }.to raise_error(Trash::UnknownKind, /expected one of page/)
  end

  it "lists what's in the trash newest first, with counts" do
    older = page("older").tap(&:discard!)
    travel 1.minute
    newer = page("newer").tap(&:discard!)

    expect(described_class.contents.map(&:last)).to eq([newer, older])
    expect(described_class.contents(kind: "page", limit: 1).map(&:last)).to eq([newer])
    expect(described_class.counts["page"]).to eq(2)
  end

  it "records restoring and purging" do
    record = page("back").tap(&:discard!)

    described_class.restore("page", record)
    expect(record.reload).not_to be_discarded
    expect(AuditLog.last).to have_attributes(action: "trash.restored", metadata: {"kind" => "page"})

    record.discard!
    described_class.purge("page", record)
    expect(Page.with_discarded.exists?(record.id)).to be(false)
    expect(AuditLog.last).to have_attributes(action: "trash.purged", target_label: "Back")
  end

  it "purges only what was trashed before the cutoff" do
    old = page("old").tap(&:discard!)
    old.update_column(:deleted_at, 40.days.ago)
    fresh = page("fresh").tap(&:discard!)

    expect(described_class.purge_expired(30.days.ago)).to eq("Page" => 1)
    expect(Page.with_discarded.pluck(:id)).to eq([fresh.id])
  end
end
