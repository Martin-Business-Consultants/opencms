# frozen_string_literal: true

# A pending "connect this machine" handshake, OAuth-device-flow style. The CLI
# mints one (unauthenticated), shows the person its short user_code, and polls
# with the long device_code. The person approves it in their signed-in browser,
# which links their user; the next poll hands the CLI their API token and burns
# the record — the token crosses the wire exactly once per handshake.
#
# A "site" handshake (the Astro installer, /frontend/install.sh) asks for the
# site's own read-only service token instead, on the Production site role;
# approving one takes settings:write, as issuing a service token does.
class DeviceAuthorization < ApplicationRecord
  # No lookalikes (0/O, 1/I/L) — someone may retype this from a terminal.
  CODE_ALPHABET = %w[2 3 4 5 6 7 8 9 A B C D E F G H J K M N P Q R S T V W X Y Z].freeze
  TTL = 15.minutes
  PURPOSES = %w[user site].freeze
  SITE_ROLE = "Production site"

  belongs_to :user, optional: true

  validates :user_code, :device_code, :expires_at, presence: true
  validates :purpose, inclusion: {in: PURPOSES}

  before_validation :generate_codes, on: :create

  scope :stale, -> { where(expires_at: ...1.day.ago) }

  def self.mint!(hostname: nil, purpose: nil, label: nil)
    create!(hostname: hostname.to_s.first(80).presence, purpose: purpose.presence_in(PURPOSES) || "user",
      label: label.to_s.first(80).presence)
  end

  def site? = purpose == "site"

  # Who may approve it: anyone for themselves; a site's token only someone
  # who may issue service tokens.
  def approvable_by?(user) = user.present? && (!site? || user.can?("settings:write"))

  # Codes are entered by hand, so accept "abcd-efgh", "ABCDEFGH", etc.
  def self.find_by_user_code(code)
    normalized = code.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    return nil if normalized.empty?

    find_by(user_code: normalized.insert(4, "-")) if normalized.length == 8
  end

  def expired?  = expires_at.past?
  def approved? = approved_at.present? && user.present?
  def denied?   = denied_at.present?
  def pending?  = !approved? && !denied? && !expired?

  def approve!(approving_user)
    raise ArgumentError, "cannot approve with no user" unless approving_user

    update!(user: approving_user, approved_at: Time.current)
  end

  def deny! = update!(denied_at: Time.current)

  # One-shot: the poll that finds this approved gets the token and destroys the
  # handshake, so a leaked device_code is worthless a moment later.
  #
  # Rotating is what makes the plaintext readable again — a CMS token is stored
  # as a digest plus an encrypted copy, and rows old enough to predate that have
  # no plaintext to hand over.
  def claim!
    raise ArgumentError, "cannot claim an unapproved authorization" unless approved?

    token, plaintext = site? ? issue_site_token : [ApiToken.for(user), nil]
    plaintext ||= token.visible? ? token.token : token.rotate!
    destroy!
    [token, plaintext]
  end

  private

  def issue_site_token
    role = Role.find_by!(name: SITE_ROLE)
    token = ServiceToken.issue(name: (label.presence || "Site build").first(60), role: role, created_by: user,
      description: "Issued to #{hostname.presence || "a site"} by the Astro installer.")
    [token, token.token]
  end

  def generate_codes
    self.expires_at ||= TTL.from_now
    self.device_code ||= "cmsd_#{SecureRandom.urlsafe_base64(32)}"
    self.user_code ||= Array.new(8) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.size)] }.join.insert(4, "-")
  end
end
