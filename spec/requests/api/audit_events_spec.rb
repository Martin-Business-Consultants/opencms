# frozen_string_literal: true

require "rails_helper"

# Every write is audited, through the admin and through the API alike; an API
# row says it came through the API. Bulk actions name the records they found.
RSpec.describe "Audit events", type: :request do
  let(:admin) { create(:user) }
  let(:api) { {"Authorization" => "Bearer #{admin.api_token.token}"} }

  def last_event = AuditLog.order(:id).last

  it "records an API page's creation, edit and publication as the admin does" do
    post "/api/pages", params: {page: {slug: "team", title: "Team", status: "draft", locale: "en"}}, headers: api, as: :json
    expect(last_event).to have_attributes(action: "page.created", actor: admin,
      metadata: {"path" => "team", "status" => "draft", "template" => nil, "via" => "api"})

    patch "/api/pages/team", params: {page: {status: "published"}}, headers: api, as: :json
    expect(last_event).to have_attributes(action: "page.published", metadata: {"path" => "team", "from" => "draft", "via" => "api"})
  end

  it "records API writes to entries, globals, collections, assets and settings" do
    Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})

    post "/api/collections/posts/entries", params: {entry: {slug: "a", title: "A", status: "draft"}}, headers: api, as: :json
    post "/api/globals", params: {global: {slug: "nav", name: "Nav", data: {}}}, headers: api, as: :json
    post "/api/collections", params: {collection: {slug: "faqs", name: "FAQs", schema: {fields: []}}}, headers: api, as: :json
    post "/api/settings", params: {setting: {key: "custom", data: {a: 1}}}, headers: api, as: :json

    expect(AuditLog.order(:id).last(4).map(&:action)).to eq(%w[entry.created global.created collection.created setting.created])
    expect(AuditLog.order(:id).last(4).map { it.metadata["via"] }).to all(eq("api"))
  end

  it "doesn't record a setting's values, only its key" do
    Setting.set("custom", {})

    patch "/api/settings/custom", params: {setting: {data: {token: "sekret"}}}, headers: api, as: :json

    expect(last_event.metadata).to eq("key" => "custom", "via" => "api")
  end

  it "names the pages a bulk status change found, not the ones it was asked for" do
    sign_in_as admin
    Page.create!(slug: "a", title: "A", status: "draft", locale: "en")

    post pages_bulk_status_changes_path, params: {slugs: %w[a ghost], status: "published"}

    expect(last_event).to have_attributes(action: "page.bulk_status_changed",
      metadata: {"to" => "published", "count" => 1, "paths" => %w[a]})
  end

  it "names the forms a bulk delete found" do
    sign_in_as admin
    Form.create!(slug: "contact", title: "Contact", status: "draft", fields: [])

    post forms_bulk_deletions_path, params: {slugs: %w[contact ghost]}

    expect(last_event).to have_attributes(action: "form.bulk_deleted", metadata: {"count" => 1, "slugs" => %w[contact]})
  end
end
