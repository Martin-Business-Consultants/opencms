# frozen_string_literal: true

# Read-only view of the tags the site runs. For a build that injects its own
# script tags, and for an agent asked "what tracking is installed?".
class Api::ScriptsController < Api::BaseController
  include PluginGated
  plugin :consent_scripts

  enforce_authorization
  requires_capability "scripts:read", only: [:index]

  def index
    @scripts = Script.ordered
  end
end
