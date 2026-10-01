# frozen_string_literal: true

require "rails_helper"

# The API used to drop `parent_id` from its permitted params, so hierarchies
# created over the API silently flattened and consumers worked around it by
# storing the real URL in frontmatter. These specs pin the fix.
#
RSpec.describe "API page hierarchy", type: :request do
  SUBDOMAIN = "hierspec"

  # `pages:publish` matters here, and not because these examples publish
  # anything: `GatedWrites` diverts a write to a *published* record into a
  # Revision when the actor can't publish, answering 202 with the revision
  # instead of the updated page. These examples edit published pages to check
  # path resync, so without publish they'd assert against a gate response and
  # never reach the hierarchy code they exist to cover. Gating itself is
  # covered by spec/requests/api/gated_writes_spec.rb.
  let(:token) do
    role = Role.find_or_create_by!(name: "API test")
    role.update!(permissions: ["pages:read", "pages:write", "pages:publish"])

    user = User.find_or_create_by!(email: "api@#{SUBDOMAIN}.example.com") do |u|
      u.name = "API"
      u.password = "password1234"
      u.password_confirmation = "password1234"
    end
    user.update!(role: role)
    ApiToken.for(user).token
  end

  let(:headers) { {"Authorization" => "Bearer #{token}"} }

  before do
    SiteSetup.new(
      name:        "Hierarchy Spec",
      owner_email: "owner@#{SUBDOMAIN}.example.com",
    ).call

    # Start every example from an empty Pages table (including the bootstrap
    # `home` page and any soft-deleted rows, which still hold their slug
    # against uniqueness).
    # Deepest-first so a child is never orphaned ahead of its parent — the
    # self-referential parent_id foreign key rejects the other order.
    Page.unscoped.order(depth: :desc).destroy_all
  end

  def create_page(attrs)
    post "/api/pages", params: {page: attrs}, headers: headers, as: :json
    JSON.parse(response.body)["page"]
  end

  it "nests a child under its parent and computes the full path" do
    parent = create_page(slug: "guides", title: "Guides", status: "published", locale: "en")
    expect(response).to have_http_status(:created)
    expect(parent["path"]).to eq("guides")

    child = create_page(
      slug: "moving-day", title: "Moving Day", status: "published", locale: "en",
      parent_id: parent["id"],
    )

    expect(response).to have_http_status(:created)
    expect(child["parent_id"]).to eq(parent["id"])
    expect(child["path"]).to eq("guides/moving-day")
    expect(child["depth"]).to eq(1)
  end

  it "addresses a nested page by its full path" do
    parent = create_page(slug: "guides", title: "Guides", status: "published", locale: "en")
    create_page(slug: "moving-day", title: "Moving Day", status: "published",
      locale: "en", parent_id: parent["id"])

    get "/api/pages/guides/moving-day", headers: headers

    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body).dig("page", "title")).to eq("Moving Day")
  end

  it "exposes the tree fields in the index so consumers can rebuild the hierarchy" do
    parent = create_page(slug: "guides", title: "Guides", status: "published", locale: "en")
    create_page(slug: "moving-day", title: "Moving Day", status: "published",
      locale: "en", parent_id: parent["id"])

    get "/api/pages", headers: headers

    rows = JSON.parse(response.body)["pages"]
    child = rows.find { |p| p["slug"] == "moving-day" }
    expect(child).to include("path" => "guides/moving-day", "parent_id" => parent["id"], "depth" => 1)
  end

  it "re-parents an existing page and resyncs the path" do
    a = create_page(slug: "alpha", title: "Alpha", status: "published", locale: "en")
    b = create_page(slug: "beta",  title: "Beta",  status: "published", locale: "en")
    child = create_page(slug: "leaf", title: "Leaf", status: "published", locale: "en", parent_id: a["id"])
    expect(child["path"]).to eq("alpha/leaf")

    patch "/api/pages/alpha/leaf", params: {page: {parent_id: b["id"]}}, headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body).dig("page", "path")).to eq("beta/leaf")
  end
end
