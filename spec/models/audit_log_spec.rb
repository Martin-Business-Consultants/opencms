# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLog do
  describe ".record" do
    it "captures actor metadata at write time" do
      user = create(:user, name: "Alice", email: "alice@example.com")

      log = described_class.record(action: "page.deleted", actor: user)

      expect(log.action).to eq("page.deleted")
      expect(log.actor_id).to eq(user.id)
      expect(log.actor_type).to eq("User")
      expect(log.actor_label).to eq("alice@example.com")
    end

    it "labels the actor as 'system' when none is provided" do
      log = described_class.record(action: "scheduled.publish")
      expect(log.actor_label).to eq("system")
      expect(log.actor_id).to be_nil
    end

    it "describes the target and stamps a label" do
      role = Role.create!(name: "Editor", permissions: ["pages:read"])
      log = described_class.record(action: "role.created", target: role)

      expect(log.target_type).to eq("Role")
      expect(log.target_id).to eq(role.id)
      expect(log.target_label).to eq("Editor")
    end

    it "swallows errors so a failed log write doesn't break the action" do
      allow(described_class).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect(described_class.record(action: "x")).to be_nil
    end
  end

  describe "scopes" do
    it "filters by actor" do
      a = create(:user); b = create(:user)
      described_class.record(action: "x", actor: a)
      described_class.record(action: "x", actor: b)

      expect(described_class.for_actor(a).count).to eq(1)
    end
  end
end
