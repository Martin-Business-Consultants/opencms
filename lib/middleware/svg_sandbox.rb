# frozen_string_literal: true

# Serves every SVG response under a policy that stops it from running script.
#
# SVG is a document format, not just an image: opened directly (rather than
# through an <img> tag) it can carry <script>, event handlers and
# <foreignObject> HTML, all executing on this origin. That origin hosts the
# admin app, so an uploaded logo must not be able to act as
# the signed-in user. Active Storage serves SVGs inline (see
# config/application.rb) so the consumer site can use them in <img>; this
# middleware makes that safe:
#
#   * `sandbox` puts the document in a unique opaque origin with scripts,
#     forms and plugins disabled — no cookies, no same-origin requests.
#   * `default-src 'none'` blocks any external fetches the file might make;
#     `img-src data:` and `style-src 'unsafe-inline'` keep ordinary
#     self-contained SVGs (embedded rasters, <style> blocks) rendering.
#   * `nosniff` stops a browser second-guessing the declared type.
#
# The headers have no effect when the SVG is used as an <img> (images never
# run script anyway); they only bite when the file is navigated to.
#
# It sits at the top of the middleware stack and applies to any response
# whose Content-Type is image/svg+xml — Active Storage's disk/proxy
# controllers, public/ static files, anything else — rather than matching
# on paths.
class SvgSandbox
  CONTENT_SECURITY_POLICY = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; sandbox"

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    if svg?(headers)
      headers = Rack::Headers[headers] unless headers.is_a?(Rack::Headers)
      headers["content-security-policy"] = CONTENT_SECURITY_POLICY
      headers["x-content-type-options"] = "nosniff"
    end

    [status, headers, body]
  end

  private

  def svg?(headers)
    type = headers["content-type"] || headers["Content-Type"]
    type.to_s.split(";").first.to_s.strip.casecmp?("image/svg+xml")
  end
end
