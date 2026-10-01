# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User 2FA" do
  let(:user) { create(:user) }

  describe "#enable_totp!" do
    it "rejects a wrong code" do
      user.setup_totp_secret!
      success, codes = user.enable_totp!("000000")
      expect(success).to eq(false)
      expect(codes).to eq([])
      expect(user.reload.totp_enabled?).to eq(false)
    end

    it "enables when the code is right and returns recovery codes once" do
      user.setup_totp_secret!
      now = Time.current.to_i
      code = TwoFactor.code_at(user.totp_secret, now / TwoFactor::STEP_SECONDS)

      success, codes = user.enable_totp!(code)
      expect(success).to eq(true)
      expect(codes.size).to eq(TwoFactor::RECOVERY_CODES)
      expect(user.reload.totp_enabled?).to eq(true)
      expect(user.recovery_code_digests.size).to eq(codes.size)
    end
  end

  describe "#consume_recovery_code" do
    it "removes a matched digest and returns true; otherwise false" do
      user.setup_totp_secret!
      code = TwoFactor.code_at(user.totp_secret, Time.current.to_i / TwoFactor::STEP_SECONDS)
      _, codes = user.enable_totp!(code)

      first = codes.first
      expect(user.consume_recovery_code(first)).to eq(true)
      expect(user.consume_recovery_code(first)).to eq(false) # second use rejected
      expect(user.reload.recovery_code_digests.size).to eq(codes.size - 1)
    end
  end

  describe "#disable_totp!" do
    it "wipes the secret + codes" do
      user.setup_totp_secret!
      code = TwoFactor.code_at(user.totp_secret, Time.current.to_i / TwoFactor::STEP_SECONDS)
      user.enable_totp!(code)

      user.disable_totp!
      expect(user.reload.totp_enabled?).to eq(false)
      expect(user.totp_secret).to be_nil
      expect(user.recovery_code_digests).to eq([])
    end
  end
end
