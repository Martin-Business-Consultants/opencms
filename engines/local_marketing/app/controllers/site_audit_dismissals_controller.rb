# frozen_string_literal: true

# "Not a problem here." A person's answer to a site-audit finding, kept
# apart from the snapshot that raised it so it holds across runs — see
# Reports::Dismissals. Restoring one brings it back onto the list.
class SiteAuditDismissalsController < ApplicationController
  include PluginGated
  plugin :local_marketing

  # Deciding what the audit's list means is working on the business's
  # behalf, like running a report or managing a citation — same capability.
  requires_capability "reports:run", only: [:create, :destroy]

  KEY_FORMAT = /\A[a-z0-9:_\-\.]+\z/i

  def create
    key = params[:key].to_s
    return redirect_back fallback_location: dashboard_path, alert: "Unknown finding." unless key.match?(KEY_FORMAT)

    Reports::Dismissals.dismiss!(key, by: Current.user, note: params[:note])
    redirect_back fallback_location: dashboard_path, notice: "Dismissed. It won't come back unless you restore it."
  end

  def destroy
    key = params[:key].to_s
    Reports::Dismissals.restore!(key)
    redirect_back fallback_location: dashboard_path, notice: "Restored."
  end
end
