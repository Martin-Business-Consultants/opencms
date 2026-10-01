# frozen_string_literal: true

# Content migration — Tools › Import over the API.
#
#   GET    /api/tools/import             — what's importable, what's here now
#   POST   /api/tools/import/:source     — start one (Api::Tools::Imports::RunsController)
#   DELETE /api/tools/import/wipe        — reset content surfaces (Api::Tools::Imports::WipesController)
#
# Imports are asynchronous: the response is 202 with the job queued, not a
# finished import. Poll `GET /api/manifest` counts to see it land.
class Api::Tools::ImportsController < Api::BaseController
  include PluginGated
  plugin :importers

  enforce_authorization
  requires_capability "tools:use", only: :show

  def show
  end
end
