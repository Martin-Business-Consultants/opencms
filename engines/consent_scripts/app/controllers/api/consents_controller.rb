# frozen_string_literal: true

# The consent payload for a build that renders its own banner. Capability-
# free like the other build-facing reads (manifest, sitemap, redirects): a
# token is required, a role is not — the same bytes are public at
# /consent.json on the site's own host.
class Api::ConsentsController < Api::BaseController
  include PluginGated
  plugin :consent_scripts

  def show
  end
end
