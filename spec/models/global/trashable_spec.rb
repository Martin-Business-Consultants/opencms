# frozen_string_literal: true

require "rails_helper"

RSpec.describe Global::Trashable do
  def make(slug) = Global.create!(slug: slug, name: slug.titleize, schema: {"fields" => []}, data: {})

  it "trashes a global, recording it first" do
    global = make("footer")

    global.trash

    expect(Global.with_discarded.find(global.id)).to be_discarded
    expect(AuditLog.last).to have_attributes(action: "global.deleted", target_id: global.id, metadata: {"slug" => "footer"})
  end

  it "trashes a set of globals under one event naming them" do
    Global.trash_all([make("a"), make("b")])

    expect(Global.count).to eq(0)
    expect(AuditLog.last).to have_attributes(action: "global.bulk_deleted", target: nil, metadata: {"count" => 2, "slugs" => %w[a b]})
  end

  it "records nothing for an empty set" do
    expect { Global.trash_all([]) }.not_to change(AuditLog, :count)
  end
end
