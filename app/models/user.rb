# frozen_string_literal: true

class User < ApplicationRecord
  include ListSearchable

  search_on :name, :email

  include Eventable
  include TwoFactorAuthentication

  has_secure_password

  generates_token_for :email_verification, expires_in: 2.days do
    email
  end

  generates_token_for :password_reset, expires_in: 20.minutes do
    password_salt.last(10)
  end


  belongs_to :role, optional: true

  has_many :sessions, dependent: :destroy

  # Exactly one, minted with the account so every user — admins included —
  # has an API token waiting for them the first time they look. See ApiToken.
  has_one :api_token, dependent: :destroy

  after_create :ensure_api_token

  # Authorization entrypoint. Returns true if the user's role grants the
  # capability (or holds the wildcard). Returns false when the user has no
  # role — controllers must explicitly opt out for sign-in / public flows.
  def can?(capability)
    role&.has_capability?(capability) || false
  end

  def admin?
    role&.admin? || false
  end

  # The user's API token, minting it if the account predates the token
  # backfill or the row was deleted out from under us.
  def api_token! = ApiToken.for(self)

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: {with: URI::MailTo::EMAIL_REGEXP}
  validates :password, allow_nil: true, length: {minimum: 8}

  normalizes :email, with: -> { _1.strip.downcase }

  before_validation if: :email_changed?, on: :update do
    self.verified = false
  end

  after_update if: :password_digest_previously_changed? do
    sessions.where.not(id: Current.session).delete_all
  end

  private

  def ensure_api_token
    ApiToken.for(self)
  end
end
