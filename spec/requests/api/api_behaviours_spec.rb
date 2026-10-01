# frozen_string_literal: true

require "rails_helper"
require "zip"

# Smaller API behaviours: bulk uploads take assets:write
# and are audited, a preview draft resolves its assets, a flag needs a value,
# a card datetime may come without a zone, and entry.updated rows carry the
# entry's status.
RSpec.describe "API behaviours", type: :request do
  let(:admin) { create(:user) }

  def api(user) = {"Authorization" => "Bearer #{user.api_token.token}"}

  def json = JSON.parse(response.body)

  describe "POST /api/bulk_uploads" do
    let(:zip) do
      Tempfile.new(["up", ".zip"]).tap do |file|
        Zip::OutputStream.open(file.path) { it.put_next_entry("a.txt"); it.write("hi") }
      end
    end

    def archive = Rack::Test::UploadedFile.new(zip.path, "application/zip")

    it "needs assets:write" do
      reader = create(:user, admin: false, role: create(:role, permissions: %w[assets:read]))

      post "/api/bulk_uploads", params: {archive: archive}, headers: api(reader)

      expect(response).to have_http_status(:forbidden)
      expect(json).to include("capability" => "assets:write")
      expect(BulkUpload.count).to eq(0)
    end

    it "is recorded as the file manager's upload is" do
      post "/api/bulk_uploads", params: {archive: archive}, headers: api(admin)

      expect(response).to have_http_status(:created)
      expect(AuditLog.last).to have_attributes(action: "assets.bulk_upload_queued")
      expect(AuditLog.last.metadata).to include("folder" => "/", "via" => "api")
    end
  end

  it "resolves a preview draft's assets" do
    BlockType.seed
    asset = Asset.create!(name: "pic.png", folder: "/", file: {io: StringIO.new("x"), filename: "pic.png", content_type: "image/png"})
    Page.create!(slug: "home", title: "Home", status: "published")

    post "/api/preview_drafts", params: {page_slug: "home", title: "Draft", blocks: [{id: "b1", type: "image", data: {asset_id: asset.id, alt: "a"}}]},
      headers: api(admin), as: :json
    get "/api/preview_drafts/#{json["token"]}?resolve=assets"

    expect(json["assets"].keys).to eq([asset.id.to_s])
    expect(json.dig("assets", asset.id.to_s, "filename")).to eq("pic.png")
  end

  describe "entry fields" do
    let(:collection) do
      Collection.create!(slug: "specials", name: "Specials", schema: {"fields" => [
        {"name" => "active", "type" => "boolean"}, {"name" => "starts_at", "type" => "datetime"}
      ]})
    end
    let!(:entry) { collection.entries.create!(slug: "tacos", title: "Tacos", status: "draft", frontmatter: {"active" => true}) }

    it "refuses a flag with no value rather than storing null" do
      patch "/api/collections/specials/entries/tacos/toggle_field", params: {field: "active"}, headers: api(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(entry.reload.frontmatter).to eq("active" => true)
    end

    it "takes a datetime-local value, in the server's zone (UTC here) when the site names none" do
      patch "/api/collections/specials/entries/tacos/update_field", params: {field: "starts_at", value: "2026-10-01T09:30"},
        headers: api(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(entry.reload.frontmatter["starts_at"]).to eq("2026-10-01T09:30:00Z")
    end

    it "reads a datetime-local value in the site's timezone when it has one" do
      Setting.set("general", Setting.get("general").merge("timezone" => "America/Chicago"))

      patch "/api/collections/specials/entries/tacos/update_field", params: {field: "starts_at", value: "2026-10-01T09:30"},
        headers: api(admin), as: :json

      expect(entry.reload.frontmatter["starts_at"]).to eq("2026-10-01T14:30:00Z")
    end

    it "falls back to the server's zone, as the admin board does" do
      allow(Site).to receive(:server_time_zone).and_return(Time.find_zone("Asia/Tokyo"))

      patch "/api/collections/specials/entries/tacos/update_field", params: {field: "starts_at", value: "2026-10-01T09:30"},
        headers: api(admin), as: :json

      expect(entry.reload.frontmatter["starts_at"]).to eq("2026-10-01T00:30:00Z")
    end

    it "names the entry's status on entry.updated, as page.updated does" do
      patch "/api/collections/specials/entries/tacos", params: {entry: {title: "Fish tacos"}}, headers: api(admin), as: :json

      expect(AuditLog.last).to have_attributes(action: "entry.updated")
      expect(AuditLog.last.metadata).to include("status" => "draft")
    end
  end
end
