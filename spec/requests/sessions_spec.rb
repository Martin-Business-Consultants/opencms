# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:user) { create(:user) }

  describe "GET /new" do
    it "returns http success" do
      get sign_in_url
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /sign_in" do
    context "with valid credentials" do
      it "redirects to pages" do
        post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}
        expect(response).to redirect_to(pages_url)

        get pages_url
        expect(response).to have_http_status(:success)
      end
    end

    context "with invalid credentials" do
      before { sign_out }

      it "redirects to the sign in url with an alert" do
        post sign_in_url, params: {email: user.email, password: "SecretWrong1*3"}
        expect(response).to redirect_to(sign_in_url)
        expect(flash[:alert]).to eq("That email or password is incorrect")

        get dashboard_url
        expect(response).to redirect_to(sign_in_url)
      end
    end
  end

  describe "DELETE /sign_out" do
    before { sign_in_as user }

    it "signs this device out and lands on sign in" do
      delete session_url(user.sessions.last)
      expect(response).to redirect_to(sign_in_url)

      get settings_sessions_url
      expect(response).to redirect_to(sign_in_url)
    end

    it "signs another device out and stays on the sessions list" do
      other = user.sessions.create!

      delete session_url(other)

      expect(response).to redirect_to(settings_sessions_url)
      expect(user.sessions.exists?(other.id)).to be(false)
      follow_redirect!
      expect(response).to have_http_status(:success)
    end
  end
end
