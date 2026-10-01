# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiToken do
  let(:user) { create(:user) }

  describe ".for" do
    it "returns the token minted alongside the user" do
      expect(described_class.for(user)).to eq(user.api_token)
    end

    it "mints one when the row is missing" do
      user.api_token.destroy!
      user.reload

      token = described_class.for(user)

      expect(token).to be_persisted
      expect(token.token).to start_with("mbc_")
      expect(token.prefix).to eq(token.token.first(described_class::PREFIX_LENGTH))
      expect(token.token_digest).to eq(described_class.digest(token.token))
    end

    it "is idempotent — a user only ever has one" do
      user.api_token # create the user (and their token) before counting

      expect { 3.times { described_class.for(user) } }
        .not_to change(described_class, :count)
    end
  end

  describe "storage" do
    it "keeps the plaintext readable but not in the clear" do
      token = described_class.for(user)
      raw   = described_class.connection.select_value("SELECT token FROM api_tokens WHERE id = #{token.id.to_i}")

      expect(token.reload.token).to start_with("mbc_")
      expect(raw).to be_present
      expect(raw).not_to include(token.token)
    end
  end

  describe ".authenticate" do
    it "returns the record for a valid plaintext" do
      token = described_class.for(user)
      expect(described_class.authenticate(token.token)).to eq(token)
    end

    it "returns nil for an unknown plaintext" do
      expect(described_class.authenticate("mbc_not_a_real_token")).to be_nil
    end

    it "returns nil for a blank plaintext" do
      expect(described_class.authenticate("")).to be_nil
    end
  end

  describe "#rotate!" do
    it "issues a new secret and stops honouring the old one" do
      token = described_class.for(user)
      old   = token.token

      new_plaintext = token.rotate!

      expect(new_plaintext).not_to eq(old)
      expect(token.reload.token).to eq(new_plaintext)
      expect(token.prefix).to eq(new_plaintext.first(described_class::PREFIX_LENGTH))
      expect(described_class.authenticate(old)).to be_nil
      expect(described_class.authenticate(new_plaintext)).to eq(token)
    end

    it "clears the usage trail — it's a different credential now" do
      token = described_class.for(user)
      token.record_use!(ip: "10.0.0.1")

      token.rotate!

      expect(token.reload.last_used_at).to be_nil
      expect(token.last_used_ip).to be_nil
    end
  end

  describe "#visible?" do
    it "is false for tokens minted before plaintext was stored" do
      token = described_class.for(user)
      token.update_columns(token: nil)

      expect(token.reload.visible?).to eq(false)
    end
  end

  describe "#can?" do
    it "grants exactly what the owner's role grants" do
      role = create(:role, permissions: ["pages:read"])
      u    = create(:user, admin: false, role: role)

      expect(u.api_token.can?("pages:read")).to eq(true)
      expect(u.api_token.can?("pages:write")).to eq(false)
    end

    it "follows the role live — demoting the user constrains the token" do
      role  = create(:role, permissions: ["pages:read", "pages:write"])
      u     = create(:user, admin: false, role: role)
      token = u.api_token

      role.update!(permissions: ["pages:read"])

      expect(token.reload.can?("pages:write")).to eq(false)
    end
  end

  describe "#record_use!" do
    it "stamps last_used_at and ip" do
      token = described_class.for(user)
      token.record_use!(ip: "10.0.0.1")

      expect(token.last_used_at).to be_within(2.seconds).of(Time.current)
      expect(token.last_used_ip).to eq("10.0.0.1")
    end

    it "is throttled — repeated calls within the window are no-ops" do
      token = described_class.for(user)
      token.record_use!(ip: "10.0.0.1")
      first = token.last_used_at

      token.record_use!(ip: "10.0.0.2")

      expect(token.reload.last_used_at).to eq(first)
      expect(token.last_used_ip).to eq("10.0.0.1")
    end
  end
end
