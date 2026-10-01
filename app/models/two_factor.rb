# frozen_string_literal: true

require "openssl"
require "securerandom"

# Minimal RFC 6238 TOTP and recovery-code helpers. Built on stdlib so we
# don't take a `rotp` dependency for the few things we need.
#
# Layout:
#   * `random_secret` — base32 string, 16 chars (80 bits) — what we store
#     on the user and put into the otpauth URI.
#   * `valid?(secret, code)` — returns true if `code` matches the TOTP
#     for any of the windows in `WINDOW_DRIFT` around now (±1 step).
#   * `provisioning_uri(secret, account_label, issuer)` — `otpauth://totp/...`
#     URI that auth apps consume when scanned/pasted.
module TwoFactor
  STEP_SECONDS    = 30
  CODE_DIGITS     = 6
  WINDOW_DRIFT    = (-1..1).freeze        # accept previous + current + next step
  ALGORITHM       = "SHA1"                # what Google / 1Password / Authy default to
  BASE32_CHARS    = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
  RECOVERY_CODES  = 10
  RECOVERY_BYTES  = 8                     # → 16-char hex

  module_function

  def random_secret(bytes: 10)
    encode_base32(SecureRandom.bytes(bytes))
  end

  # Generate `RECOVERY_CODES` plaintext recovery codes plus a parallel array
  # of SHA-256 digests for storage. Plaintexts are shown once and never
  # returned again.
  def generate_recovery_codes
    plaintexts = Array.new(RECOVERY_CODES) { SecureRandom.hex(RECOVERY_BYTES) }
    digests    = plaintexts.map { |p| digest_recovery(p) }
    [plaintexts, digests]
  end

  def digest_recovery(code)
    OpenSSL::Digest::SHA256.hexdigest(code.to_s.strip.downcase)
  end

  def valid?(secret, code, at: Time.current.to_i)
    return false if secret.blank? || code.blank?

    normalized = code.to_s.gsub(/\s+/, "")
    return false unless normalized.match?(/\A\d{#{CODE_DIGITS}}\z/)

    counter = at / STEP_SECONDS
    WINDOW_DRIFT.any? { |drift| code_at(secret, counter + drift) == normalized }
  end

  def code_at(secret, counter)
    bytes = decode_base32(secret)
    raw_counter = [counter].pack("Q>") # 8-byte big-endian
    hmac = OpenSSL::HMAC.digest(ALGORITHM, bytes, raw_counter)
    offset = hmac.bytes.last & 0x0f
    bin = ((hmac.bytes[offset] & 0x7f) << 24) |
          ((hmac.bytes[offset + 1] & 0xff) << 16) |
          ((hmac.bytes[offset + 2] & 0xff) << 8) |
          (hmac.bytes[offset + 3] & 0xff)
    (bin % 10 ** CODE_DIGITS).to_s.rjust(CODE_DIGITS, "0")
  end

  def provisioning_uri(secret, account:, issuer: "MBC CMS")
    params = {
      secret:    secret,
      issuer:    issuer,
      algorithm: ALGORITHM,
      digits:    CODE_DIGITS,
      period:    STEP_SECONDS
    }
    label = "#{issuer}:#{account}"
    "otpauth://totp/#{uri_encode(label)}?#{params.map { |k, v| "#{k}=#{uri_encode(v.to_s)}" }.join("&")}"
  end

  def encode_base32(bytes)
    bits = bytes.bytes.flat_map { |b| b.to_s(2).rjust(8, "0").chars }.join
    chunks = bits.scan(/.{1,5}/)
    out = chunks.map { |c| BASE32_CHARS[c.ljust(5, "0").to_i(2)] }.join
    pad = (8 - (out.length % 8)) % 8
    out + ("=" * pad)
  end

  def decode_base32(string)
    cleaned = string.to_s.upcase.gsub(/[^A-Z2-7]/, "")
    bits = cleaned.chars.map { |c| BASE32_CHARS.index(c).to_s(2).rjust(5, "0") }.join
    bits.scan(/.{8}/).map { |b| b.to_i(2).chr }.join.b
  end

  def uri_encode(value)
    value.to_s.gsub(/[^A-Za-z0-9_.\-~]/) { |ch| ch.bytes.map { |b| "%%%02X" % b }.join }
  end
end
