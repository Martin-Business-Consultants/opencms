# frozen_string_literal: true

# The build hook that republishes the public site — Settings › Deploy over
# the API.
#
#   GET   /api/deploy          — hook config, last status, recent attempts
#   PATCH /api/deploy          — set the provider (build_hook, github) or URL, pause/unpause
#   POST  /api/deploy/trigger  — deploy now (Api::Deploys::TriggersController)
#
# An agent that just changed published content should be able to ship it,
# and — more importantly — be able to see whether the deploy that followed
# actually succeeded, rather than reporting "done" on a build that failed.
class Api::DeploysController < Api::BaseController
  enforce_authorization
  requires_capability "settings:read",  only: [:show]
  requires_capability "settings:write", only: [:update]

  agent_summary(:show, :update) do |payload|
    d = payload["deploy"] or next nil
    state = if !d["url_set"] then "are not configured — no build hook set"
    elsif d["paused"] then "are paused"
    else "are ready (#{d["url_host"]})"
    end
    last = d["last_status"].presence ? " · last build #{d["last_status"]}" : ""
    "Deploys #{state}#{last}."
  end
  agent_breadcrumbs(:show) do |payload|
    d = payload["deploy"] || {}
    if d["paused"]
      [crumb("Let builds run again", "cms deploy resume")]
    elsif d["url_set"]
      [crumb("Ship what's published now", "cms deploy now"),
        crumb("Stop builds for a while", "cms deploy pause")]
    else
      [crumb("Point it at a build hook",
        %(cms patch /deploy '{"deploy":{"url":"https://…"}}'))]
    end
  end

  def show
  end

  def update
    Deploys.configure(params.require(:deploy).permit(:provider, :url, :paused))
    render :show
  end
end
