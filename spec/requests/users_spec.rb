# frozen_string_literal: true

require "rails_helper"

# /sign_up makes the install's owner, once. After that the CMS is
# invitation-only.
RSpec.describe "Users", type: :request do
  describe "GET /sign_up" do
    it "offers the owner account on a fresh install" do
      get sign_up_url

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Create the owner account")
    end

    it "is closed once anyone has an account" do
      create(:user)

      get sign_up_url

      expect(response).to redirect_to(sign_in_url)
      expect(flash[:alert]).to match(/invitation-only/)
    end
  end

  describe "POST /sign_up" do
    it "makes the first account the owner, with the site bootstrapped" do
      expect { post sign_up_url, params: attributes_for(:user) }.to change(User, :count).by(1)

      expect(response).to redirect_to(pages_url)
      expect(User.last).to be_admin
      expect(Role.find_by(name: "Editor")).to be_present
    end

    it "refuses a second account" do
      create(:user)

      expect { post sign_up_url, params: attributes_for(:user) }.not_to change(User, :count)
      expect(response).to redirect_to(sign_in_url)
    end
  end

  describe "the sign-in page" do
    it "links to the owner account only while there are no accounts" do
      get sign_in_url
      expect(response.body).to include("Create the owner account")

      create(:user)
      get sign_in_url
      expect(response.body).not_to include("Create the owner account")
    end
  end
end
