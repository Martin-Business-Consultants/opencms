# frozen_string_literal: true

# The admin side of the sitemap over the API: the full tree, rows excluded
# from the published sitemap included (GET /api/sitemap/entries), and a
# narrow patch for one row's sitemap settings (PATCH /api/sitemap/:source/:id,
# `source` being "page" or "collection_entry"). Content edits go through the
# page and entry endpoints; this is for "noindex this, bump that one's
# priority".
class Api::SitemapEntriesController < Api::BaseController
  def index
    require_capability!("pages:read")

    sitemap = Sitemap.new
    @all = sitemap.all_entries
    @included = sitemap.entries
  end

  def update
    require_capability!("pages:write")

    @record = Sitemap.record_for(params[:source], params[:id])
    return render(json: {error: "not_found"}, status: :not_found) unless @record

    settings = params.require(:entry).permit(:status, *Sitemapped::SETTINGS)

    if settings.key?(:status) && !Page::STATUSES.include?(settings[:status])
      render json: {error: "invalid", message: "status must be one of #{Page::STATUSES.join(", ")}"},
        status: :unprocessable_content
    else
      if settings.key?(:status) && settings[:status] != @record.status
        require_capability!(Sitemap.publish_capability(params[:source]))
      end

      @record.status = settings[:status] if settings.key?(:status)
      @record.change_sitemap_settings(settings.except(:status))
      @record.save!

      @record.track_sitemap_update(source: params[:source])
    end
  end
end
