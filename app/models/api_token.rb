# frozen_string_literal: true

require "openssl"
require "securerandom"

# Every user carries exactly one API token, minted on demand and readable
# for as long as it lives — `ApiToken.for(user)` returns it, creating it the
# first time. The owner can look at it, copy it, and rotate it; there is no
# expiry and no revocation, because rotating *is* revocation.
#
# Storage is belt-and-braces: `token_digest` (SHA-256) is what
# authentication looks up — indexed, unique, and the only column consulted
# on the hot path — while `token` holds the encrypted plaintext purely so
# the settings screen can show it again. Rows created before this design
# (migration `PersonalizeApiTokens`) have a digest but no plaintext; they
# still authenticate, they just can't be displayed until rotated. Ask
# `visible?` before reaching for `token`.
#
# Authentication flow (Api::BaseController):
#
#   1. Pull `Authorization: Bearer <plaintext>` off the request.
#   2. ApiToken.authenticate(plaintext) → record-or-nil, hashing the input
#      and looking up by digest.
#   3. Stamp `last_used_at` (≤ once per minute) and set `Current.api_user`
#      and `Current.api_token`.
#
# A token has no permissions of its own: `can?` defers entirely to the
# owner's role, evaluated per request. Demote the user and every request
# their token makes is constrained from the next call onward.
class ApiToken < ApplicationRecord
  include Eventable

  PREFIX            = "mbc_"
  PLAINTEXT_BYTES   = 32                              # 32 bytes → 43 url-safe chars
  PREFIX_LENGTH     = 12                              # "mbc_" + 8 chars
  USE_THROTTLE      = 1.minute                        # last_used_at not bumped more often than this

  # Non-deterministic: nothing ever queries by plaintext (that's the
  # digest's job), so there's no reason to accept the weaker mode.
  encrypts :token

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :prefix,       presence: true
  validates :user_id,      uniqueness: true

  scope :ordered, -> { order(created_at: :desc) }
  scope :used,    -> { where.not(last_used_at: nil) }

  # The user's token, created on first ask. Safe to call on every page
  # render — it's a single indexed lookup once the row exists.
  def self.for(user)
    find_by(user_id: user.id) || create_for(user)
  end

  # Handles the race where two requests both find no token: the unique
  # index on user_id decides, the loser reads the winner's row.
  def self.create_for(user)
    create!(user: user, **columns_for(generate_plaintext))
  rescue ActiveRecord::RecordNotUnique
    find_by!(user_id: user.id)
  end

  # Looks up a token by plaintext. Returns the record on hit, nil on miss.
  # Constant-time work is delegated to the DB index lookup — we never
  # iterate tokens.
  def self.authenticate(plaintext)
    return nil if plaintext.to_s.empty?

    find_by(token_digest: digest(plaintext))
  end

  def self.generate_plaintext
    "#{PREFIX}#{SecureRandom.urlsafe_base64(PLAINTEXT_BYTES)}"
  end

  def self.digest(plaintext)
    OpenSSL::Digest::SHA256.hexdigest(plaintext.to_s)
  end

  # The three columns derived from a plaintext, in one place so minting and
  # rotating can't drift apart.
  def self.columns_for(plaintext)
    {
      token:        plaintext,
      token_digest: digest(plaintext),
      prefix:       plaintext.first(PREFIX_LENGTH)
    }
  end

  # Issues a fresh secret in place and returns the plaintext. The old one
  # stops authenticating the moment this commits — there's no grace window,
  # so anything using it has to be updated.
  def rotate!
    plaintext = self.class.generate_plaintext
    update!(**self.class.columns_for(plaintext), last_used_at: nil, last_used_ip: nil)
    track_event(:rotated, prefix: prefix)
    plaintext
  end

  # False for tokens minted before plaintext was stored — they work, they
  # just can't be shown. Rotating fixes it.
  def visible? = token.present?

  # The plaintext, for its owner asking to see it — each look is recorded.
  def reveal
    track_event(:revealed)
    token
  end

  def masked = "#{prefix}#{"•" * 8}"

  # Throttled write — `last_used_at` only updates once per `USE_THROTTLE`
  # window. Avoids hammering the DB for high-traffic API consumers.
  def record_use!(ip:)
    return if last_used_at && last_used_at > USE_THROTTLE.ago

    update_columns(last_used_at: Time.current, last_used_ip: ip)
  end

  # A token is exactly as capable as its owner, checked live. Nothing is
  # frozen at mint time, so there is no stale grant to clean up.
  def can?(capability)
    user&.can?(capability) || false
  end
end
