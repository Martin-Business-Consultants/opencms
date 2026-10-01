# frozen_string_literal: true

require "rails_helper"

# One audit vocabulary (STYLE.md, Events): the admin and the API record the
# same act under the same action and metadata, and only `via: "api"` tells
# them apart.
RSpec.describe "Audit vocabulary", type: :request do
  let(:admin) { create(:user) }
  let(:api) { {"Authorization" => "Bearer #{admin.api_token.token}"} }

  # [action, metadata without via] of the rows a block writes.
  def rows_from
    from = AuditLog.maximum(:id).to_i
    yield
    AuditLog.where("id > ?", from).order(:id).map { [it.action, it.metadata.except("via")] }
  end

  def admin_rows(&)
    sign_in_as admin
    rows_from(&)
  end

  it "names a block type's delete the same from both" do
    %w[one two].each { BlockType.create!(slug: it, label: it, fields: [], defaults: {}, version: 1) }

    from_api = rows_from { delete "/api/block_types/one", headers: api }
    from_admin = admin_rows { delete "/block_types/two" }

    expect(from_api.map(&:first)).to eq(["block_type.deleted"])
    expect(from_admin.map(&:first)).to eq(["block_type.deleted"])
  end

  it "records a Build board publish the same from both" do
    collection = Collection.create!(slug: "specials", name: "Specials",
      schema: {"fields" => [{"name" => "active", "label" => "Active", "type" => "boolean"}]},
      build_config: {"field" => "active", "also_publish" => true})
    %w[a b].each { collection.entries.create!(slug: it, title: it, status: "draft", locale: "en", frontmatter: {"active" => false}) }

    from_api = rows_from { patch "/api/collections/specials/entries/a/move", params: {on: true}, headers: api, as: :json }
    from_admin = admin_rows { post "/collections/specials/entries/b/placement", params: {column: "on"} }

    expect(from_api.map { [it[0], it[1].except("slug")] }).to eq(from_admin.map { [it[0], it[1].except("slug")] })
    expect(from_api.first).to eq(["entry.published", {"collection" => "specials", "slug" => "a", "fields" => ["active"], "to" => true, "from" => "draft"}])
  end

  it "describes a review request's page the same from both" do
    page = Page.create!(slug: "about", title: "About", status: "published", locale: "en")

    from_api = rows_from { post "/api/review_requests", params: {reviewable_type: "Page", slug: "about"}, headers: api, as: :json }
    ReviewRequest.delete_all
    from_admin = admin_rows { post "/review_requests", params: {reviewable_type: "Page", reviewable_id: page.id} }

    expect(from_api).to eq(from_admin)
    expect(from_admin.first.last["reviewable"]).to include("slug" => "about", "label" => "About")
  end

  it "records deploy settings and Deploy now the same from both" do
    from_api = rows_from do
      patch "/api/deploy", params: {deploy: {url: "https://hooks.example.test/a", provider: "build_hook"}}, headers: api, as: :json
      post "/api/deploy/trigger", headers: api
    end
    from_admin = admin_rows do
      patch "/settings/deploy", params: {settings: {url: "https://hooks.example.test/b", provider: "build_hook", paused: "0"}}
      post "/settings/deploy/trigger"
    end

    expect(from_api).to eq(from_admin)
    expect(from_admin).to eq([["settings.deploy_updated", {"url_set" => true, "paused" => false, "provider" => "build_hook"}],
      ["settings.deploy_triggered", {}]])
  end

  it "records a sitemap row edit from both" do
    page = Page.create!(slug: "about", title: "About", status: "published", locale: "en")

    from_api = rows_from { patch "/api/sitemap/page/#{page.id}", params: {entry: {sitemap_priority: 0.4}}, headers: api, as: :json }
    from_admin = admin_rows { patch "/sitemap/page/#{page.id}", params: {entry: {sitemap_priority: 0.6}} }

    expect(from_api).to eq(from_admin)
    expect(from_admin).to eq([["sitemap.entry_updated", {"source" => "page"}]])
  end

  it "records a folder rename by its normalized paths from both" do
    Asset.create!(name: "x.png", folder: "/brand/logos", file: {io: StringIO.new("x"), filename: "x.png", content_type: "image/png"})

    from_api = rows_from { patch "/api/asset_folders", params: {path: "brand/logos", to: "brand/marks/"}, headers: api, as: :json }
    from_admin = admin_rows { patch "/file_manager/folder", params: {path: "/brand/marks", to: "/brand/logos"} }

    expect(from_api.first).to eq(["asset_folder.renamed", {"from" => "/brand/logos", "to" => "/brand/marks", "moved" => 1}])
    expect(from_admin.first).to eq(["asset_folder.renamed", {"from" => "/brand/marks", "to" => "/brand/logos", "moved" => 1}])
  end

  it "records a cancelled agent run from both" do
    %i[ai agents].each { Cms::Plugins.switch!(it, on: true) }
    agent = Agent.create!(name: "Sweeper", instructions: "Audit.", capability_keys: %w[manifest read_pages])
    first, second = agent.dispatch!, agent.dispatch!

    from_api = rows_from { post "/api/agent_runs/#{first.id}/cancel", headers: api }
    from_admin = admin_rows { post "/agent_runs/#{second.id}/cancellation" }

    expect(from_api).to eq(from_admin)
    expect(from_admin).to eq([["agent_run.canceled", {"agent" => "Sweeper"}]])
  end

  it "names the site on an export and an import wipe" do
    Cms::Plugins.switch!(:importers, on: true)
    sign_in_as admin

    post "/tools/backup"
    expect(AuditLog.last.action).to eq("site_backup.exported")

    delete "/tools/import/wipe", params: {confirm: Site.key}
    expect(AuditLog.last).to have_attributes(action: "import.wiped")
    expect(AuditLog.last.metadata).to include("site" => Site.key)
    expect(AuditLog.last.metadata).not_to have_key("tenant")
  end
end
