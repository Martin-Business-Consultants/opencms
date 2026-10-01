# frozen_string_literal: true

require "rails_helper"

# Sets the site up (owner, roles, machine tokens) as a new install would.
RSpec.describe "Settings::ApiTokens", type: :request do
  SETTINGS_TOKEN_SUBDOMAIN = "tokensettings"

  def find_or_create_user(email)
    user = User.find_or_create_by!(email: email) do |u|
      u.name                  = "Owner"
      u.password              = "password1234"
      u.password_confirmation = "password1234"
      u.verified              = true
    end
    user.update!(role: Role.system_admin)
    user
  end

  let(:user)  { find_or_create_user("owner@#{SETTINGS_TOKEN_SUBDOMAIN}.example.com") }
  let(:token) { ApiToken.for(user) }

  before do
    SiteSetup.new(
      name:        "Token Settings Spec",
      owner_email: "owner@#{SETTINGS_TOKEN_SUBDOMAIN}.example.com"
    ).call

    token.rotate!
    sign_in_as user
  end

  describe "GET /settings/api_token" do
    it "renders without putting the plaintext in the page" do
      get "/settings/api_token"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(token.prefix)
      expect(response.body).not_to include(token.reload.token)
    end

    it "mints a token for a user who somehow has none" do
      token.destroy!

      expect { get "/settings/api_token" }
        .to change { ApiToken.count }.by(1)
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /settings/api_token/reveal" do
    it "swaps the plaintext into the page's secret frame and records the reveal" do
      expect {
        post "/settings/api_token/reveal"
      }.to change { AuditLog.where(action: "api_token.revealed").count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(<turbo-frame id="api_token_secret">), token.reload.token)
    end

    it "returns the plaintext as JSON when asked for JSON" do
      post "/settings/api_token/reveal", as: :json

      expect(JSON.parse(response.body)["token"]).to eq(token.reload.token)
    end

    it "410s for a token minted before plaintext was stored" do
      token.update_columns(token: nil)

      post "/settings/api_token/reveal", as: :json

      expect(response).to have_http_status(:gone)
      expect(JSON.parse(response.body)["error"]).to eq("rotation_required")
    end

    it "reveals the signed-in user's token, not someone else's" do
      other = find_or_create_user("someone-else@#{SETTINGS_TOKEN_SUBDOMAIN}.example.com")

      post "/settings/api_token/reveal", as: :json

      revealed = JSON.parse(response.body)["token"]
      expect(revealed).to eq(token.reload.token)
      expect(revealed).not_to eq(ApiToken.for(other).token)
    end
  end

  describe "POST /settings/api_token/rotation" do
    it "replaces the secret in place, keeping one token per user" do
      old = token.reload.token

      expect { post "/settings/api_token/rotation" }
        .not_to change { ApiToken.count }

      expect(response).to redirect_to("/settings/api_token")
      expect(token.reload.token).not_to eq(old)
      expect(ApiToken.authenticate(old)).to be_nil
    end
  end
end
