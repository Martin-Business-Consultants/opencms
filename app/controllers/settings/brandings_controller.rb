# frozen_string_literal: true

# Settings → Branding. Logo, colours, font, corners, shadow (Branding).
#
# Stored in the `settings` key/value table (not `globals`), since branding
# is admin-only configuration, not editorially-authored content. Keeping it
# out of Globals also keeps the Globals list focused on real site content.
# The public site reads it; the admin wears the colour and font too
# (/branding.css). Corners are the site's alone: the admin always uses one
# 3px radius (--radius in _global.css).
class Settings::BrandingsController < Settings::BaseController
  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :update

  def show
    @branding = Branding.current
    @images = Asset.images.with_attached_file.order(:name)
  end

  def update
    record = Branding.save(params.require(:branding).permit(*Branding::PERMITTED))
    Event.record("settings.branding_updated", keys: record.data.keys.sort)
    redirect_to settings_branding_path, notice: "Branding saved"
  end
end
