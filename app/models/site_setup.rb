# frozen_string_literal: true

require "securerandom"

# Setting up a new install, once: the site's starter content and roles
# (SiteBootstrap), an owner who can sign in, and the two machine tokens a
# site needs — the read-only one the Astro build holds (PRODUCTION_TOKEN)
# and the write-but-not-publish one agents use (USER_AGENT_TOKEN).
#
# Idempotent: run it again and it finds the owner and tokens rather than
# making more. `bin/rails cms:bootstrap` is the command line for it.
class SiteSetup
  Result = Struct.new(:owner_email, :admin_password, :token, :production_token, :user_agent_token,
    :created, :cms_url, keyword_init: true) do
    def to_h = super.transform_keys(&:to_s)
  end

  attr_reader :name, :owner_email, :owner_name, :password

  def initialize(name: nil, owner_email: nil, owner_name: nil, password: nil)
    @name        = name.presence || Site.key.titleize
    @owner_email = (owner_email.presence || "owner@#{Site.host.split(":").first}").to_s.strip.downcase
    @owner_name  = owner_name.presence
    @password    = password.presence
  end

  def call
    SiteBootstrap.bootstrap!(site_name: name)
    created = !User.exists?(email: owner_email)
    owner = ensure_owner!

    Result.new(
      owner_email:      owner.email,
      admin_password:   created ? generated_password : nil,
      token:            owner_token(owner),
      production_token: existing_or_issued("Production site"),
      user_agent_token: existing_or_issued("Agent"),
      created:          created,
      cms_url:          "#{Rails.configuration.x.app_protocol}://#{Site.host}"
    )
  end

  private

  def generated_password
    @generated_password ||= password || SecureRandom.urlsafe_base64(18)
  end

  def ensure_owner!
    User.find_by(email: owner_email) || User.create!(
      name:                  owner_name || owner_email.split("@").first,
      email:                 owner_email,
      password:              generated_password,
      password_confirmation: generated_password,
      verified:              true,
      role:                  Role.system_admin
    )
  end

  def owner_token(owner)
    token = ApiToken.for(owner)
    token.visible? ? token.token : token.rotate!
  end

  # Name doubles as the lookup key: one live token per job.
  def existing_or_issued(role_name)
    token = ServiceToken.active.find_by(name: role_name)
    return token.visible? ? token.token : token.rotate! if token

    ServiceToken.issue!(name: role_name, role: Role.find_by!(name: role_name),
      description: "Issued at setup.").token
  end
end
