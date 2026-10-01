# frozen_string_literal: true

# The owner's version of the Marketer's Report: what's working, what we're
# doing, and what only they can do. No costs, no agents, no report ids.
class Marketing::ClientsController < ApplicationController
  include PluginGated
  plugin :local_marketing

  requires_capability "reports:read", only: :show

  def show
    @overview = Marketing::Overview.new
  end
end
