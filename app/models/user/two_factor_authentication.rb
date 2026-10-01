# frozen_string_literal: true

# Two-factor sign-in: a TOTP secret the person enrolls with an authenticator
# app, and single-use recovery codes stored only as digests. The code
# arithmetic is TwoFactor (app/models/two_factor.rb).
module User::TwoFactorAuthentication
  extend ActiveSupport::Concern

  # Generate a fresh TOTP secret (stored unencrypted — losing the user DB
  # is already a much bigger problem than losing TOTP secrets). Doesn't
  # enable 2FA — the user must verify a code first via `enable_totp!`.
  def setup_totp_secret!
    update!(totp_secret: TwoFactor.random_secret, totp_enabled: false, totp_enabled_at: nil)
  end

  def totp_provisioning_uri
    return nil unless totp_secret.present?

    TwoFactor.provisioning_uri(totp_secret, account: email)
  end

  # Verify a 6-digit code against the current secret. Used both during
  # enrollment (before `totp_enabled` is true) and at sign-in.
  def verify_totp_code(code)
    TwoFactor.valid?(totp_secret, code)
  end

  # Enable 2FA after the user verifies they can produce valid codes.
  # Returns [true, plaintexts] on success, [false, []] if the code didn't
  # validate. Mints a fresh batch of recovery codes — show the plaintexts
  # exactly once and stash only the digests.
  def enable_totp!(code)
    return [false, []] unless verify_totp_code(code)

    plaintexts, digests = TwoFactor.generate_recovery_codes
    update!(totp_enabled: true, totp_enabled_at: Time.current, recovery_code_digests: digests)
    [true, plaintexts]
  end

  def disable_totp!
    update!(totp_secret: nil, totp_enabled: false, totp_enabled_at: nil, recovery_code_digests: [])
  end

  # Single-use recovery code: returns true and removes the code's digest
  # from the user's stash, false if no digest matches.
  def consume_recovery_code(code)
    digest = TwoFactor.digest_recovery(code)
    return false unless recovery_code_digests.is_a?(Array) && recovery_code_digests.include?(digest)

    update!(recovery_code_digests: recovery_code_digests - [digest])
    true
  end

  # Mint and store a fresh batch (digests only — plaintexts are shown once).
  def regenerate_recovery_codes!
    plaintexts, digests = TwoFactor.generate_recovery_codes
    update!(recovery_code_digests: digests)
    plaintexts
  end
end
