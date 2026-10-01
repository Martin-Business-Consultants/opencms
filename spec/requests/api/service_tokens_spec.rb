# frozen_string_literal: true

require "rails_helper"

# Managing service tokens over the API — the surface behind `cms service-token`.
# Distinct from `service_token_auth_spec.rb`, which covers authenticating *with*
# one; here a caller mints, reveals and retires them.
#
# Two things every example is really about: the secret only crosses the wire
# when someone asks for it, and `settings:write` is the gate, exactly as it is
# in the admin UI.
RSpec.describe "Api service tokens", type: :request do
  let(:admin) { create(:user) }
  # The site bootstrap already installs this role, so take the one that's
  # there — issuing against a second role of the same name would test nothing.
  let(:site_role) do
    Role.find_or_create_by!(name: "Production site") do |r|
      r.description = "Read-only. The role behind a published site's PRODUCTION_TOKEN."
      r.permissions = Permissions.defaults_for(:site)
    end
  end

  # A token is exactly as capable as its owner's role, so "a token with these
  # capabilities" means a user whose role holds exactly them.
  def auth(capabilities = nil)
    actor = capabilities ? create(:user, admin: false, role: create(:role, permissions: capabilities)) : admin
    {"Authorization" => "Bearer #{actor.api_token.token}"}
  end

  def json = JSON.parse(response.body)

  def issue(name: "Production site", role: site_role)
    ServiceToken.issue!(name: name, role: role, created_by: admin)
  end

  describe "GET /api/service_tokens" do
    it "lists tokens without the secret that would make the list dangerous" do
      token = issue

      get "/api/service_tokens", headers: auth

      expect(response).to have_http_status(:success)
      listed = json["service_tokens"].find { |t| t["id"] == token.id }
      expect(listed).to include("name" => "Production site", "role" => "Production site",
        "prefix" => token.prefix, "visible" => true, "revoked" => false)
      expect(listed["created_by"]).to eq(admin.email)
      # The prefix is 13 characters of a much longer secret; nothing in the
      # body should be the whole thing.
      expect(response.body).not_to include(token.token)
    end

    it "names the roles a token can be issued against, since --role takes a name" do
      site_role

      get "/api/service_tokens", headers: auth

      expect(json["roles"].map { |r| r["name"] }).to include("Production site")
    end

    it "requires settings:read" do
      get "/api/service_tokens", headers: auth(["pages:read"])

      expect(response).to have_http_status(:forbidden)
      expect(json["capability"]).to eq("settings:read")
    end
  end

  describe "GET /api/service_tokens/:id" do
    it "returns one token, still without plaintext" do
      token = issue

      get "/api/service_tokens/#{token.id}", headers: auth(["settings:read"])

      expect(response).to have_http_status(:success)
      expect(json["service_token"]["masked"]).to eq(token.masked)
      expect(response.body).not_to include(token.token)
    end

    it "404s on an id that isn't there" do
      get "/api/service_tokens/999999", headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/service_tokens" do
    it "issues a token and hands back the secret once" do
      post "/api/service_tokens",
        params: {name: "PRODUCTION", role_id: site_role.id, description: "Cloudflare Pages"},
        headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(json["token"]).to start_with(ServiceToken::PREFIX)
      expect(json["service_token"]).to include("name" => "PRODUCTION", "role" => "Production site",
        "description" => "Cloudflare Pages", "revoked" => false)

      minted = ServiceToken.find(json["service_token"]["id"])
      expect(json["token"]).to eq(minted.token)
      expect(minted.created_by).to eq(admin)
    end

    it "audits the issue without writing the secret into the audit row" do
      post "/api/service_tokens", params: {name: "PRODUCTION", role_id: site_role.id},
        headers: auth, as: :json

      entry = AuditLog.order(:id).last
      expect(entry.action).to eq("service_token.issued")
      expect(entry.metadata).to include("name" => "PRODUCTION", "role" => "Production site", "via" => "api")
      expect(entry.metadata.to_json).not_to include(json["token"])
    end

    it "accepts the role by name, which is what the CLI passes" do
      site_role

      post "/api/service_tokens", params: {name: "PRODUCTION", role: "Production site"},
        headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(json["service_token"]["role"]).to eq("Production site")
    end

    it "matches a role name case-insensitively" do
      site_role

      post "/api/service_tokens", params: {name: "PRODUCTION", role: "production site"},
        headers: auth, as: :json

      expect(response).to have_http_status(:created)
    end

    it "says which roles exist rather than minting an unscoped token" do
      site_role

      post "/api/service_tokens", params: {name: "PRODUCTION"}, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("role_required")
      expect(json["message"]).to include("Production site")
      expect(ServiceToken.find_by(name: "PRODUCTION")).to be_nil
    end

    it "rejects a blank name — a nameless credential can't be recognised later" do
      post "/api/service_tokens", params: {name: "  ", role_id: site_role.id}, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to have_key("name")
      expect(ServiceToken.where(name: "")).to be_empty
    end

    it "requires settings:write, not merely settings:read" do
      post "/api/service_tokens", params: {name: "PRODUCTION", role_id: site_role.id},
        headers: auth(["settings:read"]), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json["capability"]).to eq("settings:write")
      expect(ServiceToken.find_by(name: "PRODUCTION")).to be_nil
    end
  end

  describe "POST /api/service_tokens/:id/reveal" do
    it "returns the secret and records who asked" do
      token = issue

      post "/api/service_tokens/#{token.id}/reveal", headers: auth

      expect(response).to have_http_status(:success)
      expect(json["token"]).to eq(token.reload.token)

      entry = AuditLog.order(:id).last
      expect(entry.action).to eq("service_token.revealed")
      expect(entry.metadata).to include("name" => "Production site", "via" => "api")
    end

    it "410s for a token minted before plaintext was stored — it works, it just can't be read" do
      token = issue
      token.update_column(:token, nil)

      post "/api/service_tokens/#{token.id}/reveal", headers: auth

      expect(response).to have_http_status(:gone)
      expect(json["error"]).to eq("rotation_required")
    end

    it "requires settings:write — reading a secret is not a read" do
      token = issue

      post "/api/service_tokens/#{token.id}/reveal", headers: auth(["settings:read"])

      expect(response).to have_http_status(:forbidden)
      expect(json["capability"]).to eq("settings:write")
    end
  end

  describe "POST /api/service_tokens/:id/rotate" do
    it "returns the new secret and kills the old one immediately" do
      token = issue
      old_plaintext = token.token

      post "/api/service_tokens/#{token.id}/rotate", headers: auth

      expect(response).to have_http_status(:success)
      expect(json["token"]).to start_with(ServiceToken::PREFIX)
      expect(json["token"]).not_to eq(old_plaintext)
      expect(json["token"]).to eq(token.reload.token)

      expect(ServiceToken.authenticate(old_plaintext)).to be_nil
      expect(ServiceToken.authenticate(json["token"])).to eq(token)

      expect(AuditLog.order(:id).last.action).to eq("service_token.rotated")
    end

    it "requires settings:write" do
      token = issue

      post "/api/service_tokens/#{token.id}/rotate", headers: auth(["settings:read"])

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/service_tokens/:id/revoke" do
    it "stops the token authenticating but keeps the row, so audit rows still resolve" do
      token = issue
      plaintext = token.token

      post "/api/service_tokens/#{token.id}/revoke", headers: auth

      expect(response).to have_http_status(:success)
      expect(json["service_token"]["revoked"]).to be(true)
      expect(json).not_to have_key("token")

      expect(ServiceToken.authenticate(plaintext)).to be_nil
      expect(ServiceToken.find_by(id: token.id)).to be_present

      expect(AuditLog.order(:id).last.action).to eq("service_token.revoked")
    end

    it "requires settings:write" do
      token = issue

      post "/api/service_tokens/#{token.id}/revoke", headers: auth(["settings:read"])

      expect(response).to have_http_status(:forbidden)
      expect(token.reload).not_to be_revoked
    end
  end

  # The case the whole design is for: a leaked PRODUCTION_TOKEN reads what the
  # site already shows the world, and cannot mint itself something wider.
  describe "a service token acting on this endpoint" do
    def as_service(role)
      {"Authorization" => "Bearer #{ServiceToken.issue!(name: "Acting", role: role).token}"}
    end

    it "can't list tokens on a read-only site role" do
      get "/api/service_tokens", headers: as_service(site_role)

      expect(response).to have_http_status(:forbidden)
      expect(json["capability"]).to eq("settings:read")
    end

    it "can read but not mint on a role with settings:read alone" do
      role = create(:role, permissions: ["settings:read"])

      get "/api/service_tokens", headers: as_service(role)
      expect(response).to have_http_status(:success)

      post "/api/service_tokens", params: {name: "Wider", role_id: site_role.id},
        headers: as_service(role), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "can't reveal another token's secret without settings:write" do
      target = issue
      role = create(:role, permissions: ["settings:read"])

      post "/api/service_tokens/#{target.id}/reveal", headers: as_service(role)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include(target.token)
    end

    it "mints with no person behind it, and the row says so" do
      role = create(:role, permissions: ["settings:read", "settings:write"])

      post "/api/service_tokens", params: {name: "Minted by a machine", role_id: site_role.id},
        headers: as_service(role), as: :json

      expect(response).to have_http_status(:created)
      expect(json["service_token"]["created_by"]).to be_nil
      expect(ServiceToken.find(json["service_token"]["id"]).created_by).to be_nil
    end
  end
end
