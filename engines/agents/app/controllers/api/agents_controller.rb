# frozen_string_literal: true

# An agent reading its own definition.
#
# Read-only on purpose. A worker needs to know its scope, its capabilities
# and its instructions — all of which are already in the run brief — but a
# harness that could PATCH an agent could rewrite the instructions it is
# about to execute, which is the one thing the whole separation exists to
# prevent. Editing happens in the UI, under `agents:write`.
class Api::AgentsController < Api::BaseController
  include PluginGated
  plugin :agents

  enforce_authorization

  requires_capability "agents:read", only: [:index, :show]

  def index
    @agents = Agent.includes(:content_scopes).ordered
    @agents = @agents.enabled if params[:enabled].present?
  end

  def show
    @agent = Agent.find(params[:id])
  end
end
