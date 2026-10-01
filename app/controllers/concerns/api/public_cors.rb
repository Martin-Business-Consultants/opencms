# frozen_string_literal: true

# CORS for the unauthenticated write endpoints a static site posts to from the
# browser: form submissions and quote requests. Origins allowed per request,
# resolved from (in order):
#   1. The site's general Setting: `site_base_url` + `public_origins[]`
#   2. The FORM_SUBMISSIONS_ALLOWED_ORIGINS env var (deploy-wide fallback)
#   3. "*" wildcard if neither is set (dev convenience)
module Api::PublicCors
  extend ActiveSupport::Concern

  ENV_ORIGINS = (ENV["FORM_SUBMISSIONS_ALLOWED_ORIGINS"] || "").split(",").map(&:strip).reject(&:empty?).freeze

  def options
    head :no_content
  end

  private

  def set_cors_headers
    origin   = request.headers["Origin"].to_s
    allowed  = allowed_origins
    allow    = if allowed == ["*"] || allowed.empty? && ENV_ORIGINS.empty?
      "*"
    elsif allowed.include?(origin)
      origin
    end

    return unless allow

    response.set_header("Access-Control-Allow-Origin",  allow)
    response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Content-Type")
    response.set_header("Access-Control-Max-Age",       "86400")
    response.set_header("Vary",                         "Origin") unless allow == "*"
  end

  def allowed_origins
    general = Setting.get("general")
    from_setting = [origin_of(general["site_base_url"])].compact +
                   Array(general["public_origins"]).map { |u| origin_of(u) }.compact
    (from_setting + ENV_ORIGINS).uniq
  end

  def origin_of(url)
    return nil if url.to_s.strip.empty?

    uri = URI.parse(url.to_s.strip)
    return nil unless uri.scheme && uri.host

    port = uri.port
    default = (uri.scheme == "https" ? 443 : 80)
    suffix = (port && port != default) ? ":#{port}" : ""
    "#{uri.scheme}://#{uri.host}#{suffix}"
  rescue URI::InvalidURIError
    nil
  end
end
