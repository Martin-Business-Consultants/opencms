# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::BlockTypes", type: :request do
  let(:user) { create(:user) }

  # A token carries whatever its owner's role carries, so "a token with
  # these capabilities" means a user whose role holds exactly them. With no
  # argument you get the default admin's token.
  def auth_headers(capabilities = nil)
    actor =
      if capabilities
        create(:user, admin: false, role: create(:role, permissions: capabilities))
      else
        user
      end

    {"Authorization" => "Bearer #{actor.api_token.token}"}
  end

  def make_block_type(**attrs)
    BlockType.create!({
      slug:   "bt_#{SecureRandom.hex(3)}",
      label:  "Test",
      fields: []
    }.merge(attrs))
  end

  describe "GET /api/block_types" do
    it "401s without a token" do
      get "/api/block_types"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists block types" do
      make_block_type(slug: "hero", label: "Hero")
      make_block_type(slug: "cta",  label: "CTA")

      get "/api/block_types", headers: auth_headers(["block_types:read"])
      expect(response).to have_http_status(:success)

      slugs = JSON.parse(response.body).fetch("block_types").map { |bt| bt["slug"] }
      expect(slugs).to include("hero", "cta")
    end

    it "filters out deprecated when ?deprecated=false" do
      make_block_type(slug: "active",     deprecated: false)
      make_block_type(slug: "deprecated", deprecated: true)

      get "/api/block_types?deprecated=false", headers: auth_headers(["block_types:read"])
      slugs = JSON.parse(response.body).fetch("block_types").map { |bt| bt["slug"] }
      expect(slugs).to include("active")
      expect(slugs).not_to include("deprecated")
    end
  end

  describe "GET /api/block_types/:slug" do
    it "returns the block type with json_schema" do
      make_block_type(slug: "media", label: "Media", fields: [
        {"name" => "heading", "type" => "string", "required" => true}
      ])

      get "/api/block_types/media", headers: auth_headers(["block_types:read"])
      expect(response).to have_http_status(:success)

      body = JSON.parse(response.body).fetch("block_type")
      expect(body["slug"]).to eq("media")
      expect(body["json_schema"]["required"]).to eq(["heading"])
    end

    it "404s for an unknown slug" do
      get "/api/block_types/nope", headers: auth_headers(["block_types:read"])
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/block_types" do
    it "creates a block type and audits" do
      expect {
        post "/api/block_types",
          params:  {block_type: {slug: "panel", label: "Panel", fields: [
            {"name" => "title", "type" => "string"}
          ]}},
          headers: auth_headers(["block_types:write"]),
          as:      :json
      }.to change(BlockType, :count).by(1)
        .and change { AuditLog.where(action: "block_type.created").count }.by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body).dig("block_type", "slug")).to eq("panel")
      expect(BlockType.find_by(slug: "panel").built_in).to eq(false)
    end

    it "422s on invalid params" do
      post "/api/block_types",
        params:  {block_type: {slug: "Bad-Slug", label: ""}},
        headers: auth_headers(["block_types:write"]),
        as:      :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "403s without block_types:write scope" do
      post "/api/block_types",
        params:  {block_type: {slug: "x", label: "X"}},
        headers: auth_headers(["block_types:read"]),
        as:      :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/block_types/:slug" do
    it "updates fields and audits" do
      make_block_type(slug: "media", label: "Media", fields: [
        {"name" => "background", "type" => "select", "options" => %w[none muted]}
      ])

      expect {
        patch "/api/block_types/media",
          params:  {block_type: {fields: [
            {"name" => "background", "type" => "select", "options" => %w[none muted dark]}
          ]}},
          headers: auth_headers(["block_types:write"]),
          as:      :json
      }.to change { AuditLog.where(action: "block_type.updated").count }.by(1)

      expect(response).to have_http_status(:success)
      reloaded = BlockType.find_by(slug: "media")
      expect(reloaded.fields.first["options"]).to eq(%w[none muted dark])
    end

    it "422s when the schema shape is invalid" do
      make_block_type(slug: "broken")

      patch "/api/block_types/broken",
        params:  {block_type: {fields: [{"name" => "BadName", "type" => "string"}]}},
        headers: auth_headers(["block_types:write"]),
        as:      :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/block_types/:slug" do
    it "deletes and audits with delete scope" do
      make_block_type(slug: "goner")

      expect {
        delete "/api/block_types/goner", headers: auth_headers(["block_types:delete"])
      }.to change(BlockType, :count).by(-1)
        .and change { AuditLog.where(action: "block_type.deleted").count }.by(1)

      expect(response).to have_http_status(:no_content)
    end

    it "403s without block_types:delete scope" do
      make_block_type(slug: "stays")
      delete "/api/block_types/stays", headers: auth_headers(["block_types:write"])
      expect(response).to have_http_status(:forbidden)
      expect(BlockType.find_by(slug: "stays")).to be_present
    end
  end
end
