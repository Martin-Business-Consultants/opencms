# frozen_string_literal: true

# Does the key work? A real round trip on the cheapest model — the same call
# a drafting helper makes, so a green result means the helpers will work
# rather than that a string is non-empty.
class Settings::Ais::TestsController < Settings::BaseController
  include PluginGated
  plugin :ai

  requires_capability "settings:write", only: :create

  def create
    unless Ai::Zen.configured?
      return redirect_to settings_ai_path, alert: "Add a key first."
    end

    if Ai::Zen.ping
      redirect_to settings_ai_path, notice: "OpenCode Zen answered on #{Ai::Models.label("cheap")}."
    else
      redirect_to settings_ai_path, alert: "Zen replied, but not as expected. Check the key."
    end
  rescue StandardError => e
    redirect_to settings_ai_path, alert: "Zen test failed: #{e.message}"
  end
end
