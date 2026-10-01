# frozen_string_literal: true

# Settings › Reporting › Test: a real round trip to DataForSEO with the saved
# credential (Reports::ConnectionTest).
class Settings::Reportings::TestsController < Settings::BaseController
  include PluginGated
  plugin :local_marketing

  requires_capability "settings:write", only: :create

  def create
    return redirect_to settings_reporting_path, alert: "Add a login and password first." unless DataForSeo::Client.configured?

    outcome = Reports::ConnectionTest.new.run
    if outcome.ok?
      redirect_to settings_reporting_path, notice: outcome.message
    else
      redirect_to settings_reporting_path, alert: outcome.message
    end
  end
end
