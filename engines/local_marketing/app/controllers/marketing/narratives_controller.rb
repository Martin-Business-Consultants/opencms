# frozen_string_literal: true

# Rewrite the few sentences that read the numbers, now. The AI plugin writes
# them (Marketing::Narrative); without it there is no summary.
class Marketing::NarrativesController < ApplicationController
  include PluginGated
  plugin :local_marketing

  requires_capability "reports:run", only: :create

  def create
    if Marketing::Overview.new.refresh_narrative!
      redirect_to marketing_path, notice: "Summary rewritten."
    else
      redirect_to marketing_path, alert: Marketing::Narrative.available? ? "The model didn't answer; try again." : "Add an AI key under Settings → AI to get a written summary."
    end
  end
end
