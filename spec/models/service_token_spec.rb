# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceToken do
  let(:site_role)  { Role.create!(name: "Site #{SecureRandom.hex(3)}", permissions: Permissions::SITE_DEFAULT.dup) }
  let(:agent_role) { Role.create!(name: "Agent #{SecureRandom.hex(3)}", permissions: Permissions::AGENT_DEFAULT.dup) }

  describe ".issue!" do
    it "mints a readable secret with its own prefix" do
      token = described_class.issue!(name: "Production site", role: site_role)

      expect(token.token).to start_with("mbcs_")
      expect(token).to be_visible
      expect(token.prefix).to eq(token.token.first(described_class::PREFIX_LENGTH))
    end

    it "stores the digest, not the secret, as what authentication looks up" do
      token = described_class.issue!(name: "Production site", role: site_role)

      expect(token.token_digest).to eq(described_class.digest(token.token))
      expect(token.token_digest).not_to eq(token.token)
    end

    it "allows many per site, unlike a personal token" do
      described_class.issue!(name: "Production site", role: site_role)
      expect { described_class.issue!(name: "Preview build", role: site_role) }.not_to raise_error
    end
  end

  describe ".authenticate" do
    it "resolves a live token" do
      token = described_class.issue!(name: "Production site", role: site_role)
      expect(described_class.authenticate(token.token)).to eq(token)
    end

    it "refuses a revoked one" do
      token = described_class.issue!(name: "Production site", role: site_role)
      token.revoke!

      expect(described_class.authenticate(token.token)).to be_nil
    end

    it "refuses a rotated-away secret" do
      token = described_class.issue!(name: "Production site", role: site_role)
      old = token.token
      token.rotate!

      expect(described_class.authenticate(old)).to be_nil
      expect(described_class.authenticate(token.reload.token)).to eq(token)
    end

    it "is nil for nonsense" do
      expect(described_class.authenticate("")).to be_nil
      expect(described_class.authenticate("mbcs_nope")).to be_nil
    end
  end

  describe "#can?" do
    it "carries its role's capabilities, read live" do
      token = described_class.issue!(name: "Production site", role: site_role)

      expect(token.can?("pages:read")).to be(true)
      expect(token.can?("pages:write")).to be(false)

      site_role.update!(permissions: site_role.permissions + ["pages:write"])
      expect(token.reload.can?("pages:write")).to be(true)
    end

    it "grants nothing once revoked" do
      token = described_class.issue!(name: "Production site", role: site_role)
      token.revoke!

      expect(token.can?("pages:read")).to be(false)
    end

    it "gives an agent write but never publish — that's what sends its edits to review" do
      token = described_class.issue!(name: "Agent", role: agent_role)

      expect(token.can?("entries:write")).to be(true)
      expect(token.can?("entries:publish")).to be(false)
      expect(token.can?("pages:publish")).to be(false)
      expect(token.can?("globals:publish")).to be(false)
    end
  end

  describe "#revoke!" do
    it "keeps the row so the audit trail can still name it" do
      token = described_class.issue!(name: "Production site", role: site_role)
      token.revoke!

      expect(described_class.find(token.id).name).to eq("Production site")
      expect(token.revoked_at).to be_present
    end
  end

  describe "the read-only site role" do
    it "can't reach anything that changes content" do
      token = described_class.issue!(name: "Production site", role: site_role)

      %w[pages:write pages:delete pages:publish entries:write entries:delete
        globals:write assets:write users:read settings:write].each do |capability|
        expect(token.can?(capability)).to be(false), "expected #{capability} to be denied"
      end
    end
  end
end
