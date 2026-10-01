# frozen_string_literal: true

require "rails_helper"

# `cms login`: the CLI mints a code pair, a signed-in person approves the short
# code in a browser, and the next poll hands the CLI a token. Nobody copies a
# secret out of a settings page and pastes it into a terminal, which is the
# step that leaks tokens into shell history and chat logs.
RSpec.describe "Api::DeviceAuthorizations", type: :request do
  def json = JSON.parse(response.body)

  describe "POST /api/device/code" do
    it "mints a code pair without any credential at all" do
      post "/api/device/code", params: {hostname: "ted-laptop"}

      expect(response).to have_http_status(:created)
      expect(json["user_code"]).to match(/\A[0-9A-Z]{4}-[0-9A-Z]{4}\z/)
      expect(json["device_code"]).to start_with("cmsd_")
      expect(json["verification_url"]).to include("/connect")
      expect(json["interval"]).to be_positive
      expect(json["expires_in"]).to be_positive
    end

    # The URL carries the code so the person lands on a pre-filled screen. The
    # code still has to be visible in the terminal — clicking a link that
    # auto-approves whatever asked would make the second factor decorative.
    it "sends the code along in the verification URL" do
      post "/api/device/code"

      expect(json["verification_url"]).to include("code=#{json["user_code"]}")
    end

    it "records the hostname so the approval screen can say what is asking" do
      post "/api/device/code", params: {hostname: "ted-laptop"}

      expect(DeviceAuthorization.last.hostname).to eq("ted-laptop")
    end
  end

  describe "POST /api/device/token" do
    let(:user) { create(:user) }

    def mint
      post "/api/device/code", params: {hostname: "box"}
      json["device_code"]
    end

    it "202s while the person has not decided yet" do
      device_code = mint

      post "/api/device/token", params: {device_code: device_code}

      expect(response).to have_http_status(:accepted)
      expect(json["status"]).to eq("pending")
    end

    it "hands over a token once approved" do
      device_code = mint
      DeviceAuthorization.last.approve!(user)

      post "/api/device/token", params: {device_code: device_code}

      expect(response).to have_http_status(:ok)
      expect(json["token"]).to be_present
      expect(json.dig("user", "email")).to eq(user.email)
      expect(json["api_url"]).to be_present
    end

    # The token that comes back has to actually work — a login that hands over a
    # string the API then rejects is worse than no login at all.
    it "hands over a token the API accepts" do
      device_code = mint
      DeviceAuthorization.last.approve!(user)
      post "/api/device/token", params: {device_code: device_code}

      get "/api/api_tokens/me", headers: {"Authorization" => "Bearer #{json["token"]}"}

      expect(response).to have_http_status(:ok)
    end

    # One-shot. A device_code that leaks after the handshake is worthless,
    # because the handshake no longer exists.
    it "burns the handshake, so the same code cannot be redeemed twice" do
      device_code = mint
      DeviceAuthorization.last.approve!(user)

      post "/api/device/token", params: {device_code: device_code}
      expect(response).to have_http_status(:ok)

      post "/api/device/token", params: {device_code: device_code}
      expect(response).to have_http_status(:gone)
    end

    it "403s when the person declined" do
      device_code = mint
      DeviceAuthorization.last.deny!

      post "/api/device/token", params: {device_code: device_code}

      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to eq("denied")
    end

    it "410s once the codes have expired" do
      device_code = mint
      DeviceAuthorization.last.update!(expires_at: 1.minute.ago)

      post "/api/device/token", params: {device_code: device_code}

      expect(response).to have_http_status(:gone)
    end

    # An unknown code and an expired one answer the same way on purpose: telling
    # a caller which of the two it is turns the endpoint into an oracle for
    # guessing device codes.
    it "answers an unknown code the same way as an expired one" do
      post "/api/device/token", params: {device_code: "cmsd_nonsense"}

      expect(response).to have_http_status(:gone)
    end
  end

  describe "approving in the browser" do
    let(:user) { create(:user) }

    it "shows the machine that is asking, when the code is pre-filled" do
      post "/api/device/code", params: {hostname: "ted-laptop"}
      code = json["user_code"]

      sign_in_as user
      get "/connect", params: {code: code}

      expect(response.body).to include("ted-laptop")
    end

    it "links the approving person's account" do
      post "/api/device/code", params: {hostname: "box"}
      code = json["user_code"]

      sign_in_as user
      post "/connect", params: {code: code, decision: "approve"}

      expect(DeviceAuthorization.last.user).to eq(user)
      expect(DeviceAuthorization.last).to be_approved
    end

    # Typed by hand from a terminal, so case and the dash are not the person's
    # problem to get right.
    it "accepts the code however it was retyped" do
      post "/api/device/code", params: {hostname: "box"}
      code = json["user_code"]

      sign_in_as user
      post "/connect", params: {code: code.delete("-").downcase, decision: "approve"}

      expect(DeviceAuthorization.last).to be_approved
    end

    it "denying leaves nothing connected" do
      post "/api/device/code", params: {hostname: "box"}
      code = json["user_code"]

      sign_in_as user
      post "/connect", params: {code: code, decision: "deny"}

      expect(DeviceAuthorization.last).to be_denied
      expect(DeviceAuthorization.last.user).to be_nil
    end

    it "says so when the code is wrong rather than failing silently" do
      sign_in_as user
      post "/connect", params: {code: "ZZZZ-ZZZZ", decision: "approve"}

      expect(flash[:alert]).to include("expired")
    end
  end
end
