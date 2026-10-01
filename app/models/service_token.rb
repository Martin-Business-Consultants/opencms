# frozen_string_literal: true

require "openssl"
require "securerandom"

# A credential for a machine: the published site, a build pipeline, an agent.
#
# The difference from `ApiToken` is whose it is. An ApiToken belongs to a
# person and carries that person's role, which makes it the wrong thing to put
# in a site's environment — the site inherits an admin's reach, and anything
# that happens to the human (rotating their token, a role change, an account
# migration) takes production with it. A ServiceToken belongs to the site,
# names what it's for, and carries a role chosen for that job: `PRODUCTION_TOKEN`
# is read-only, `USER_AGENT_TOKEN` can write but not publish, so its edits to
# live content land in the review queue rather than on the site.
#
# Storage mirrors ApiToken deliberately — `token_digest` (SHA-256) is the only
# column authentication consults, and the encrypted `token` exists so the
# settings screen can show the secret again instead of forcing a rotation to
# read it. The `mbcs_` prefix distinguishes one at a glance from a personal
# `mbc_` token in a log or an env file.
#
# Revoking sets `revoked_at` rather than deleting: audit rows name the token
# that acted, and that name should still resolve months later.
class ServiceToken < ApplicationRecord
  include Eventable

  PREFIX = "mbcs_"
  PLAINTEXT_BYTES = 32
  PREFIX_LENGTH = 13                    # "mbcs_" + 8 chars
  USE_THROTTLE = 1.minute

  encrypts :token

  belongs_to :role
  belongs_to :created_by, class_name: "User", optional: true

  validates :name, presence: true, length: {maximum: 120}
  validates :token_digest, presence: true, uniqueness: true
  validates :prefix, presence: true

  scope :active,  -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }
  scope :ordered, -> { order(revoked_at: :asc, created_at: :desc) }

  # Mints a token and hands back the record; the plaintext is readable from it
  # until someone revokes it.
  def self.issue!(name:, role:, description: nil, created_by: nil)
    create!(
      name: name,
      role: role,
      description: description,
      created_by: created_by,
      **columns_for(generate_plaintext)
    )
  end

  # Issued by someone (the admin, the API) rather than by bootstrap, so it's
  # recorded. The actor comes from Current.
  def self.issue(name:, role:, description: nil, created_by: nil)
    issue!(name: name, role: role, description: description, created_by: created_by).tap do |token|
      token.track_event(:issued, name: token.name, role: role.name)
    end
  end

  # Revoked tokens fall out here rather than at the call site — a revoked
  # credential that still authenticates is the whole thing we're avoiding.
  def self.authenticate(plaintext)
    return nil if plaintext.to_s.empty?

    active.find_by(token_digest: digest(plaintext))
  end

  def self.generate_plaintext = "#{PREFIX}#{SecureRandom.urlsafe_base64(PLAINTEXT_BYTES)}"

  def self.digest(plaintext) = OpenSSL::Digest::SHA256.hexdigest(plaintext.to_s)

  def self.columns_for(plaintext)
    {token: plaintext, token_digest: digest(plaintext), prefix: plaintext.first(PREFIX_LENGTH)}
  end

  # Same interface as ApiToken so the authorization path doesn't care which
  # kind authenticated the request — capabilities come from the role, read
  # live, so editing the role re-scopes every token on it from the next
  # request onward.
  def can?(capability)
    return false if revoked?

    role&.has_capability?(capability) || false
  end

  def revoked? = revoked_at.present?

  def visible? = token.present?

  # The plaintext, for someone who asked to see it — each look is recorded.
  def reveal
    track_event(:revealed, name: name)
    token
  end

  def masked = "#{prefix}#{"•" * 8}"

  def capabilities
    perms = role&.permissions || []
    perms.include?(Permissions::WILDCARD) ? Permissions.all : (perms & Permissions.all)
  end

  def rotate!
    plaintext = self.class.generate_plaintext
    update!(**self.class.columns_for(plaintext), last_used_at: nil, last_used_ip: nil)
    track_event(:rotated, name: name)
    plaintext
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
    track_event(:revoked, name: name)
  end

  def record_use!(ip:)
    return if last_used_at && last_used_at > USE_THROTTLE.ago

    update_columns(last_used_at: Time.current, last_used_ip: ip)
  end

  # Audit rows label their actor by name; a service token's name is the whole
  # point of having one.
  def email = nil
end
