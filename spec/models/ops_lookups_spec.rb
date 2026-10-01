# frozen_string_literal: true

require "rails_helper"

# The small read-side objects the operational API renders.
RSpec.describe "Operational lookups" do
  it "finds a role by id, by a number in the name, or by name in any case" do
    role = Role.create!(name: "Production site", permissions: ["pages:read"])

    expect(Role.named_or_numbered(id: role.id)).to eq(role)
    expect(Role.named_or_numbered(name: role.id.to_s)).to eq(role)
    expect(Role.named_or_numbered(name: " production SITE ")).to eq(role)
    expect(Role.named_or_numbered(name: "")).to be_nil
  end

  it "records issuing and revealing a service token, and hands back the plaintext" do
    role = Role.create!(name: "Site", permissions: ["pages:read"])
    token = ServiceToken.issue(name: "Prod", role: role)

    expect(AuditLog.last).to have_attributes(action: "service_token.issued", metadata: {"name" => "Prod", "role" => "Site"})
    expect(token.reveal).to eq(token.token)
    expect(AuditLog.last.action).to eq("service_token.revealed")
  end

  it "filters the audit log and ignores times that don't parse" do
    user = create(:user, name: "Ada")
    Event.record("page.published", actor: user)
    Event.record("page.deleted", actor: user)

    expect(AuditLog.filtered(action: "page.deleted").pluck(:action)).to eq(["page.deleted"])
    expect(AuditLog.filtered(from: "garbage").count).to eq(2)
  end

  it "drops blank brand brief fields" do
    Setting.set(BrandBrief::SETTING_KEY, "brand_voice" => " Warm ", "audience" => "  ")

    expect(BrandBrief.to_h).to eq("brand_voice" => "Warm")
  end

  it "lists each owner of a reference once" do
    page = Page.create!(slug: "p", title: "P", status: "draft", locale: "en")
    2.times { |i| ContentReference.create!(owner: page, ref_type: "asset", ref_id: "7", kind: "image", position: i) }

    references, total = ContentReference.owners_of(ref_type: "asset", ref_id: "7")

    expect(total).to eq(1)
    expect(references.map(&:owner)).to eq([page])
  end

  it "puts plugins' manifest sections where they asked to sit" do
    expect(Manifest.new.to_h.keys.first(4)).to eq(%i[tenant generated_at brand counts])
    expect(Manifest.new.to_h[:version]).to eq(Cms::VERSION)
  end
end
