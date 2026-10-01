# frozen_string_literal: true

# Docs: how to work with this CMS — how it works, an Astro site, AI agents —
# and two checklists, checked against the site as it is: before going live
# (GoLiveChecklist) and site health (SiteHealth). The same are at /api/docs,
# /api/go_live, /api/site_health and `cms docs`, `cms go-live`,
# `cms site-health`.
class DocsController < ApplicationController
  requires_capability "pages:read", only: [:index, :show, :go_live, :site_health]

  before_action { @guides = Guide.all }

  def index
    @summary = GoLiveChecklist.summary
    @health = SiteHealth.summary
  end

  def show
    @guide = Guide.find(params[:slug]) or raise ActiveRecord::RecordNotFound
  end

  def go_live
    @checks = GoLiveChecklist.checks
    @summary = GoLiveChecklist.summary(@checks)
  end

  def site_health
    @checks = SiteHealth.checks
    @summary = SiteHealth.summary(@checks)
  end
end
