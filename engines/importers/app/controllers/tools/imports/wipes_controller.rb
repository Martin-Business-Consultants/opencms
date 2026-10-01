# frozen_string_literal: true

# Tools › Import › Wipe: clears imported content (Importers::ContentWipe) once
# the site's key is typed.
class Tools::Imports::WipesController < ApplicationController
  include PluginGated
  plugin :importers

  requires_capability "tools:use", only: :destroy

  def destroy
    tab = params[:tab].presence_in(Cms::Plugins.enabled_importers.keys)

    if Importers::ContentWipe.confirmed?(params[:confirm])
      counts = Importers::ContentWipe.wipe!
      Event.record("import.wiped", site: Site.key, **counts)
      redirect_to tools_import_path(tab: tab), notice: "Wiped #{summary(counts)} from “#{Site.key}”. You can run the import again."
    else
      redirect_to tools_import_path(tab: tab), alert: "Confirmation didn't match — type the workspace name exactly to wipe."
    end
  end

  private

  def summary(counts)
    wiped = counts.reject { |_, count| count.zero? }.map { |kind, count| "#{count} #{kind.to_s.tr("_", " ")}" }.join(", ")
    wiped.presence || "nothing — everything was already empty"
  end
end
