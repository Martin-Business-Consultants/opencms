# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Permissions" do
  describe "User#can?" do
    it "returns false for users with no role" do
      user = create(:user, admin: false, role: nil)
      expect(user.can?("pages:read")).to eq(false)
    end

    it "returns true when the role lists the capability" do
      role = create(:role, permissions: ["pages:read"])
      user = create(:user, admin: false, role: role)
      expect(user.can?("pages:read")).to eq(true)
      expect(user.can?("pages:write")).to eq(false)
    end

    it "returns true for any capability when the role has manage:all" do
      role = create(:role, permissions: ["manage:all"])
      user = create(:user, admin: false, role: role)
      expect(user.can?("pages:write")).to eq(true)
      expect(user.admin?).to eq(true)
    end
  end

  describe Role do
    it "rejects unknown capabilities" do
      role = build(:role, permissions: ["pages:read", "totally-bogus"])
      expect(role).not_to be_valid
      expect(role.errors[:permissions].join).to match(/totally-bogus/)
    end

    it "lazily creates the system Admin role" do
      Role.where(name: "Admin").destroy_all
      role = Role.system_admin
      expect(role.system).to eq(true)
      expect(role.permissions).to eq(["manage:all"])
      # Idempotent
      expect { Role.system_admin }.not_to change(Role, :count)
    end
  end

  describe "the canned human roles" do
    it "hold no reports, agents or findings capabilities — those are the administrator's to grant" do
      [Permissions::EDITOR_DEFAULT, Permissions::AUTHOR_DEFAULT].each do |defaults|
        expect(defaults.grep(/\A(reports|agents|recommendations):/)).to be_empty
        expect(defaults).to all(satisfy { |c| Permissions.known?(c) })
      end
    end
  end
end
