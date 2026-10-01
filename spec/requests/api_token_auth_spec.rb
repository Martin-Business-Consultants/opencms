# frozen_string_literal: true

require "rails_helper"

# Sets the site up (owner, roles, machine tokens) as a new install would.
RSpec.describe "API token auth", type: :request do
  AUTH_SPEC_SUBDOMAIN = "tokenauth"

  let(:role) do
    Role.find_or_create_by!(name: "Token auth spec") { |r| r.permissions = [] }
  end

  let(:user) do
    User.find_or_create_by!(email: "api@#{AUTH_SPEC_SUBDOMAIN}.example.com") do |u|
      u.name                  = "API"
      u.password              = "password1234"
      u.password_confirmation = "password1234"
      u.verified              = true
    end
  end

  let(:token)     { ApiToken.for(user) }
  let(:plaintext) { token.reload.token }

  def auth_headers(secret)
    {"Authorization" => "Bearer #{secret}"}
  end

  before do
    SiteSetup.new(
      name:        "Token Auth Spec",
      owner_email: "owner@#{AUTH_SPEC_SUBDOMAIN}.example.com"
    ).call

    role.update!(permissions: ["pages:read", "pages:write"])
    user.update!(role: role)
    token.rotate!
  end

  it "401s without a token" do
    get "/api/pages"
    expect(response).to have_http_status(:unauthorized)
  end

  it "401s for a rotated-away token" do
    old = plaintext
    token.rotate!

    get "/api/pages", headers: auth_headers(old)
    expect(response).to have_http_status(:unauthorized)
  end

  it "allows requests within the owner's role" do
    get "/api/pages", headers: auth_headers(plaintext)
    expect(response).to have_http_status(:success)
  end

  it "403s when the owner's role doesn't grant the capability" do
    role.update!(permissions: ["pages:read"])

    post "/api/pages",
      params:  {page: {slug: "x", title: "X", status: "draft", locale: "en"}},
      headers: auth_headers(plaintext),
      as: :json

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)["capability"]).to eq("pages:write")
  end

  it "follows the role live — demoting the user constrains an already-issued token" do
    secret = plaintext
    role.update!(permissions: ["pages:read"]) # demoted after the token existed

    post "/api/pages",
      params:  {page: {slug: "y", title: "Y", status: "draft", locale: "en"}},
      headers: auth_headers(secret),
      as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it "stamps last_used_at after a successful request" do
    expect(token.reload.last_used_at).to be_nil

    get "/api/pages", headers: auth_headers(plaintext)

    expect(token.reload.last_used_at).to be_within(5.seconds).of(Time.current)
  end

  describe "GET /api/api_tokens/me" do
    it "reports the calling token and what it can do" do
      get "/api/api_tokens/me", headers: auth_headers(plaintext)

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body.dig("token", "prefix")).to eq(token.reload.prefix)
      expect(body.dig("user", "email")).to eq(user.email)
      expect(body["capabilities"]).to match_array(["pages:read", "pages:write"])
    end
  end

  describe "POST /api/api_tokens/rotate" do
    it "returns a new plaintext and kills the one that made the call" do
      old = plaintext

      post "/api/api_tokens/rotate", headers: auth_headers(old)

      expect(response).to have_http_status(:success)
      fresh = JSON.parse(response.body)["plaintext"]
      expect(fresh).to start_with("mbc_")
      expect(fresh).not_to eq(old)

      get "/api/pages", headers: auth_headers(old)
      expect(response).to have_http_status(:unauthorized)

      get "/api/pages", headers: auth_headers(fresh)
      expect(response).to have_http_status(:success)
    end
  end
end
