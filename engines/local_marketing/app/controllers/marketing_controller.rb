# frozen_string_literal: true

# The Marketer's Report — the front page of the Marketing group.
#
# One page a marketer opens on Monday: the pillar scores against the
# business's targets, the handful of things to do next and who should do
# them, what the agents did, and a few sentences that read the numbers
# (Marketing::Overview). The owner's version is Marketing::ClientsController;
# running the baseline, handing work to an agent and rewriting the summary
# are their own resources under Marketing::.
class MarketingController < ApplicationController
  include PluginGated
  plugin :local_marketing

  requires_capability "reports:read", only: :show

  def show
    @overview = Marketing::Overview.new
  end
end
