# frozen_string_literal: true

require "rails_helper"

# Decision 7: one time zone, the site's (Settings › General), for everything
# the admin shows and reads; stored times stay UTC and the API keeps UTC.
RSpec.describe "The site's time zone", type: :request do
  let(:admin) { create(:user) }

  before do
    sign_in_as admin
    Setting.set("general", Setting.get("general").merge("timezone" => "America/Chicago"))
  end

  def draft(attrs = {})
    Page.create!({slug: "p-#{SecureRandom.hex(3)}", title: "Draft", status: "draft"}.merge(attrs))
  end

  it "is chosen in Settings › General, and only a real zone is kept" do
    patch settings_general_path, params: {settings: {timezone: "Europe/Paris"}}
    expect(Setting.get("general")["timezone"]).to eq("Europe/Paris")

    patch settings_general_path, params: {settings: {timezone: "Mars/Olympus"}}
    expect(Setting.get("general")["timezone"]).to eq("Europe/Paris")
  end

  it "offers one option per zone, labelled with every name Rails gives it" do
    Setting.set("general", Setting.get("general").merge("timezone" => "Asia/Tokyo"))

    get settings_general_path

    expect(response.body).to include(%(<option selected="selected" value="Asia/Tokyo">(GMT+09:00) Osaka, Sapporo, Tokyo</option>))
  end

  it "names the zone in a list's Updated time" do
    page = draft
    page.update_columns(updated_at: Time.utc(2026, 10, 1, 14, 30))

    get pages_path

    expect(response.body).to include("October 01, 2026 09:30 CDT")
  end

  it "shows a schedule in the site's zone and reads a typed one back in it, stored as UTC" do
    page = draft(publish_at: Time.utc(2026, 10, 1, 14, 30, 0))

    get edit_page_path(page.path)
    expect(response.body).to include(%(value="2026-10-01T09:30:00"), "America/Chicago")

    patch page_path(page.path), params: {page: {title: "Draft", publish_at: "2026-10-02T08:00:00"}}
    expect(page.reload.publish_at).to eq(Time.utc(2026, 10, 2, 13, 0, 0))
  end

  it "keeps an untouched schedule exactly, fractions of a second and all" do
    stored = Time.utc(2026, 10, 1, 14, 30, 20, 481_000)
    page = draft(publish_at: stored)

    patch page_path(page.path), params: {page: {title: "Renamed", publish_at: "2026-10-01T09:30:20"}}

    expect(page.reload.title).to eq("Renamed")
    expect(page.publish_at.usec).to eq(481_000)
  end

  it "leaves the API's times in UTC" do
    page = draft(publish_at: Time.utc(2026, 10, 1, 14, 30, 0))

    get "/api/pages/#{page.path}", headers: {"Authorization" => "Bearer #{admin.api_token.token}"}

    expect(response.parsed_body.dig("page", "updated_at")).to end_with("Z")
    expect(response.body).not_to match(/-0[56]:00"/)
  end
end

RSpec.describe ContentForm, "datetime fields" do
  let(:fields) { [{"name" => "starts", "type" => "datetime"}] }

  def decode(posted, original)
    Time.use_zone("America/Chicago") { described_class.object(fields, {"starts" => posted}, original: original, block_types: {}) }
  end

  it "reads a typed time in the site's zone and stores it as UTC" do
    expect(decode("2026-10-01T09:30", {})).to eq("starts" => "2026-10-01T14:30:00.000Z")
  end

  it "keeps an untouched value as it was stored" do
    expect(decode("2026-10-01T09:30:20", {"starts" => "2026-10-01T14:30:20.481Z"})).to eq("starts" => "2026-10-01T14:30:20.481Z")
  end
end
