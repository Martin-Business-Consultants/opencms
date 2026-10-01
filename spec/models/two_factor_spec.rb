# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwoFactor do
  describe ".random_secret" do
    it "is base32 encoded" do
      secret = described_class.random_secret
      expect(secret).to match(/\A[A-Z2-7=]+\z/)
      expect(secret.length).to be >= 16
    end
  end

  describe ".valid?" do
    let(:secret) { described_class.random_secret }

    it "accepts a code generated for the current time step" do
      now = Time.current.to_i
      code = described_class.code_at(secret, now / described_class::STEP_SECONDS)
      expect(described_class.valid?(secret, code, at: now)).to eq(true)
    end

    it "accepts a code from the previous step (clock drift tolerance)" do
      now = Time.current.to_i
      previous = described_class.code_at(secret, (now / described_class::STEP_SECONDS) - 1)
      expect(described_class.valid?(secret, previous, at: now)).to eq(true)
    end

    it "rejects a code from way in the past" do
      now = Time.current.to_i
      stale = described_class.code_at(secret, (now / described_class::STEP_SECONDS) - 10)
      expect(described_class.valid?(secret, stale, at: now)).to eq(false)
    end

    it "rejects garbage" do
      expect(described_class.valid?(secret, "abcdef")).to eq(false)
      expect(described_class.valid?(secret, "")).to eq(false)
    end
  end

  describe ".generate_recovery_codes" do
    it "yields parallel plaintexts and digests" do
      plaintexts, digests = described_class.generate_recovery_codes
      expect(plaintexts.size).to eq(described_class::RECOVERY_CODES)
      expect(digests.size).to eq(plaintexts.size)
      expect(digests.first).to eq(described_class.digest_recovery(plaintexts.first))
    end
  end

  describe ".provisioning_uri" do
    it "is a valid otpauth URI" do
      uri = described_class.provisioning_uri("ABC", account: "alice@example.com", issuer: "MBC CMS")
      expect(uri).to start_with("otpauth://totp/")
      expect(uri).to include("secret=ABC")
      expect(uri).to include("issuer=MBC%20CMS")
    end
  end
end
