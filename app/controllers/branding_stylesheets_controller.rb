# frozen_string_literal: true

# GET /branding.css — the site's colour and font as overrides of the Hotwire
# admin's tokens (Branding#stylesheet). A stylesheet rather than a <style> tag
# so views never carry inline CSS; public, because the sign-in page wears the
# branding too and nothing in it is secret.
class BrandingStylesheetsController < ApplicationController
  skip_authorization
  skip_before_action :authenticate

  def show
    record = Setting.find_by(key: Branding::KEY)
    if stale?(etag: [record&.updated_at, Branding::FONTS.keys], public: true)
      render plain: Branding.current.stylesheet, content_type: "text/css"
    end
  end
end
