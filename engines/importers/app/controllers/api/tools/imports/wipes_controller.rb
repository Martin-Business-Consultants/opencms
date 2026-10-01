# frozen_string_literal: true

# DELETE /api/tools/import/wipe — destroys Pages, Collections (and their
# entries), BlockTypes and Globals (Importers::ContentWipe). Guarded the same
# way the admin path is: `confirm` must equal the site's key.
class Api::Tools::Imports::WipesController < Api::BaseController
  include PluginGated
  plugin :importers

  enforce_authorization
  requires_capability "tools:use", only: :destroy

  def destroy
    if Importers::ContentWipe.confirmed?(params[:confirm])
      @counts = Importers::ContentWipe.wipe!
      Event.record("import.wiped", site: Site.key, **@counts)
    else
      message = "Pass confirm=#{Site.key} to wipe this workspace."
      render json: {error: "confirmation_mismatch", message: message}, status: :unprocessable_content
    end
  end
end
