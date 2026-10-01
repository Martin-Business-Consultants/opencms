# frozen_string_literal: true

# The public face of consent management: the embed the site loads, and the
# same payload as JSON for a site that renders its own banner.
#
# Unauthenticated by design — these run in visitors' browsers on the
# site's own domain, which the CMS has no session on. The payload holds
# nothing that isn't already visible in the page source of any site that
# runs these tags. CORS is open for the same reason.
class ConsentController < ApplicationController
  include PluginGated
  plugin :consent_scripts

  skip_authorization
  skip_before_action :authenticate, raise: false
  skip_forgery_protection

  before_action :allow_cross_origin

  def script
    expires_in 5.minutes, public: true
    render js: Consent::Embed.new.to_js
  end

  def show
    expires_in 5.minutes, public: true
    render json: Consent::Embed.new.payload
  end

  private

  def allow_cross_origin
    response.set_header("Access-Control-Allow-Origin", "*")
    response.set_header("Access-Control-Allow-Methods", "GET, OPTIONS")
  end
end
