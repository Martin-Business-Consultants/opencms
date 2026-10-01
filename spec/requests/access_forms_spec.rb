# frozen_string_literal: true

require "rails_helper"

# Users' and roles' new and edit pages: the editors' two-thirds / one-third
# layout, the record's own fields beside a Save box.
RSpec.describe "User and role forms", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "lays out a user's new and edit pages with the role and saving to the side" do
    get new_user_path
    expect(response.body).to include("content-form--thirds", "Add user", "Email is verified")

    other = create(:user, name: "Sam")
    get edit_user_path(other)
    expect(response.body).to include("content-form--thirds", "Save changes", "They can no longer sign in to this workspace.")

    patch user_path(other), params: {user: {name: "Samantha", email: other.email, role_id: other.role_id, password: "", password_confirmation: ""}}
    expect(other.reload.name).to eq("Samantha")
  end

  it "lays out a role's new and edit pages, locking a system role" do
    get new_role_path
    expect(response.body).to include("content-form--thirds", "Add role", "Permissions")

    role = create(:role, name: "Writer", permissions: %w[pages:read])
    get edit_role_path(role)
    expect(response.body).to include("content-form--thirds", "Save changes", "Users holding it are left with no role.")

    system = Role.find_by(system: true) || create(:role, system: true)
    get edit_role_path(system)
    expect(response.body).to include("A system role. It can’t be edited or deleted.")
    expect(response.body).not_to include("publish-box__primary")
  end
end
