# frozen_string_literal: true

require "rails_helper"

# The Settings screens on the Hotwire stack: the section index, and the pages
# whose behaviour isn't covered by their own spec files.
RSpec.describe "Settings pages", type: :request do
  let(:admin) { create(:user) }

  def sign_in_with(capabilities)
    sign_in_as create(:user, admin: false, role: create(:role, permissions: capabilities))
  end

  def totp_now(secret) = TwoFactor.code_at(secret, Time.current.to_i / TwoFactor::STEP_SECONDS)

  describe "the index" do
    it "lists the sections a role can open" do
      sign_in_with(["pages:read"])

      get settings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Profile", "Two-factor")
      # The workspace's settings need settings:read.
      expect(response.body).not_to include("Branding", "GitHub", "Service tokens", "Consent")
    end

    it "lists the workspace's settings for a role with settings:read" do
      sign_in_with(%w[pages:read settings:read])

      get settings_path

      expect(response.body).to include("Profile", "General", "Branding", "GitHub", "Deploy", "Service tokens")
    end

    it "renders every section for an admin" do
      sign_in_as admin
      Cms::Plugins.switch!(:commerce, on: true)
      Cms::Plugins.switch!(:ai, on: true)
      Cms::Plugins.switch!(:local_marketing, on: true)

      %w[/settings /settings/general /settings/profile /settings/email /settings/password /settings/two_factor
        /settings/sessions /settings/api_token /settings/service_tokens /settings/branding /settings/brand
        /settings/github /settings/commerce /settings/ai /settings/reporting /settings/deploy /settings/consent /settings/forms
        /settings/appearance].each do |path|
        get path
        expect(response).to have_http_status(:ok), "#{path} returned #{response.status}"
      end
    end
  end

  describe "profile" do
    it "saves the name" do
      sign_in_as admin

      patch settings_profile_path, params: {name: "New Name"}

      expect(response).to redirect_to(settings_profile_path)
      expect(admin.reload.name).to eq("New Name")
    end

    it "deletes the account only with the right password" do
      sign_in_as admin

      delete settings_profile_path, params: {password_challenge: "wrong"}
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Password challenge is invalid")
      expect(User.exists?(admin.id)).to be(true)

      delete settings_profile_path, params: {password_challenge: "Secret1*3*5*"}
      expect(response).to redirect_to(sign_in_path)
      expect(User.exists?(admin.id)).to be(false)
    end
  end

  describe "two-factor" do
    it "enables with a valid code and shows the recovery codes once" do
      sign_in_as admin
      get settings_two_factor_path
      secret = admin.reload.totp_secret

      post settings_two_factor_activation_path, params: {code: "000000"}
      expect(response).to have_http_status(:unprocessable_content)
      expect(admin.reload.totp_enabled?).to be(false)

      post settings_two_factor_activation_path, params: {code: totp_now(secret)}
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Save your recovery codes")
      expect(admin.reload.totp_enabled?).to be(true)
      expect(AuditLog.last.action).to eq("two_factor.enabled")

      get settings_two_factor_path
      expect(response.body).not_to include("Save your recovery codes")
    end

    it "regenerates codes and disables" do
      sign_in_as admin
      admin.setup_totp_secret!
      admin.enable_totp!(totp_now(admin.totp_secret))
      old_digests = admin.reload.recovery_code_digests

      post settings_two_factor_recovery_codes_path
      expect(response.body).to include("Save your recovery codes")
      expect(admin.reload.recovery_code_digests).not_to eq(old_digests)

      delete settings_two_factor_path
      expect(response).to redirect_to(settings_two_factor_path)
      expect(admin.reload.totp_enabled?).to be(false)
    end
  end

  describe "service tokens" do
    let(:role) { create(:role, permissions: ["pages:read"]) }

    it "issues, reveals into the row's frame, rotates and revokes" do
      sign_in_as admin

      post settings_service_tokens_path, params: {name: "Production site", role_id: role.id}
      token = ServiceToken.last
      expect(response).to redirect_to(settings_service_tokens_path)

      post settings_service_token_reveal_path(token)
      expect(response.body).to include(%(<turbo-frame id="secret_service_token_#{token.id}">), token.reload.token)
      expect(AuditLog.last.action).to eq("service_token.revealed")

      old = token.token
      post settings_service_token_rotation_path(token)
      expect(token.reload.token).not_to eq(old)

      post settings_service_token_revocation_path(token)
      expect(token.reload.revoked?).to be(true)
    end

    it "shows tokens to a reader without letting them reveal one" do
      token = ServiceToken.issue!(name: "Build", role: role)
      sign_in_with(["settings:read"])

      get settings_service_tokens_path
      expect(response.body).to include("Build")
      expect(response.body).not_to include("Issue a token", settings_service_token_reveal_path(token))

      post settings_service_token_reveal_path(token)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "branding" do
    it "saves the identity and serves the colour and font as the admin's tokens" do
      sign_in_as admin

      patch settings_branding_path, params: {branding: {primary_color: "#b45309", font: "Lora", border_radius: "large", logo_id: ""}}

      expect(response).to redirect_to(settings_branding_path)
      expect(Setting.get("branding")).to eq("primary_color" => "#b45309", "font" => "Lora", "border_radius" => "large")

      get settings_branding_path
      expect(response.body).to include("/branding.css", "fonts.googleapis.com/css2?family=Lora")
      # Corners are the public site's; the admin keeps its one 3px radius.
      expect(response.body).not_to include("data-radius")

      get branding_stylesheet_path
      expect(response.media_type).to eq("text/css")
      expect(response.body).to include("--color-link: #b45309;", %(--font-sans: "Lora"))
    end

    it "leaves anything that isn't a hex colour or a listed font out of the stylesheet" do
      Setting.set("branding", {"primary_color" => "red; } body { display: none", "font" => "Comic Sans\"; }"})

      get branding_stylesheet_path

      expect(response.body).to eq("")
    end
  end

  describe "general" do
    it "saves the hours rows that were filled in" do
      sign_in_as admin

      patch settings_general_path, params: {settings: {title: "Acme", public_origins_raw: "https://a.test\nhttps://b.test",
        hours: [{day: "Monday", hours: "9–5"}, {day: "", hours: ""}]}}

      general = Setting.get("general")
      expect(general["title"]).to eq("Acme")
      expect(general["public_origins"]).to eq(%w[https://a.test https://b.test])
      expect(general["hours"]).to eq([{"day" => "Monday", "hours" => "9–5"}])
    end

    it "records which fields changed, never their values" do
      sign_in_as admin
      Setting.set("general", {"title" => "Acme", "phone" => "555"})

      patch settings_general_path, params: {settings: {title: "Acme", phone: "556", email_from_address: "news@acme.test"}}

      row = AuditLog.where(action: "settings.general_updated").last
      expect(row.metadata["fields"]).to contain_exactly("phone", "email_from_address")
      expect(row.metadata.to_json).not_to include("556", "news@acme.test")

      expect { patch settings_general_path, params: {settings: {title: "Acme", phone: "556", email_from_address: "news@acme.test"}} }
        .not_to(change { AuditLog.where(action: "settings.general_updated").count })
    end
  end

  describe "deploy" do
    it "asks for a hook before triggering" do
      sign_in_as admin

      post settings_deploy_trigger_path

      expect(flash[:alert]).to eq("Set up a deploy provider first")
    end
  end

  describe "brand context" do
    it "overwrites the brief, so a cleared field is cleared" do
      sign_in_as admin
      Setting.set("brand", {"audience" => "Bakers"})

      patch settings_brand_path, params: {settings: {brand_voice: " Warm ", audience: ""}}

      expect(Setting.get("brand")).to include("brand_voice" => "Warm", "audience" => "")
    end
  end
end
