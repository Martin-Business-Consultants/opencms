# frozen_string_literal: true

# Queue every report the business type recommends (or every runnable one) —
# one press, with the cost shown beforehand on the page.
class Marketing::BaselinesController < ApplicationController
  include PluginGated
  plugin :local_marketing

  requires_capability "reports:run", only: :create

  def create
    baseline = Marketing::Overview.new.run_baseline(requested_by: Current.user)

    notice = "Queued #{baseline.queued} report#{baseline.queued == 1 ? "" : "s"}."
    notice += " Couldn't queue #{baseline.problems.length}: #{baseline.problems.first(2).join("; ")}" if baseline.problems.any?
    redirect_to marketing_path, notice: notice
  end
end
