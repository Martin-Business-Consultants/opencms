# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authorization", type: :request do
  let(:reader_role) { create(:role, name: "Reader", permissions: ["pages:read"]) }
  let(:reader)     { create(:user, admin: false, role: reader_role) }
  let(:no_role)    { create(:user, admin: false, role: nil) }

  describe "controllers that declare requires_capability" do
    it "lets a user with the right capability through" do
      sign_in_as reader
      get pages_url
      expect(response).to have_http_status(:success)
    end

    it "blocks a user without the right capability" do
      sign_in_as reader
      get new_page_url
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to match(/permission/i)
    end

    it "blocks a user with no role at all" do
      sign_in_as no_role
      get pages_url
      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "skip_authorization controllers" do
    it "lets any signed-in user load the dashboard" do
      sign_in_as no_role
      get dashboard_url
      expect(response).to have_http_status(:success)
    end

    it "lets any signed-in user load their settings profile" do
      sign_in_as no_role
      get settings_profile_url
      expect(response).to have_http_status(:success)
    end
  end

  describe "public controllers" do
    it "still lets unauthenticated visitors hit the sign-in page" do
      sign_out
      get sign_in_url
      expect(response).to have_http_status(:success)
    end
  end

  describe "RolesController write" do
    it "blocks a Reader from creating a role" do
      sign_in_as reader
      post roles_url, params: {role: {name: "X", description: "y", permissions: ["pages:read"]}}
      expect(response).to redirect_to(dashboard_path)
    end

    it "lets an Admin create a role with the new permissions field" do
      admin = create(:user)  # default factory grants Admin
      sign_in_as admin

      post roles_url, params: {role: {name: "X", description: "y", permissions: ["pages:read", "pages:write"]}}

      created = Role.find_by(name: "X")
      expect(created.permissions).to contain_exactly("pages:read", "pages:write")
    end

    it "rejects edits to a system role" do
      admin = create(:user)
      sign_in_as admin
      system_admin = Role.system_admin

      patch role_url(system_admin), params: {role: {name: "Hijacked", permissions: ["pages:read"]}}

      expect(response).to redirect_to(edit_role_path(system_admin))
      expect(flash[:alert]).to match(/system roles/i)
      expect(system_admin.reload.name).to eq("Admin")
    end
  end
end
