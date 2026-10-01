# frozen_string_literal: true

# Settings → Reporting. The DataForSEO credential, and the local business
# every report is about.
#
# Two halves in one page on purpose. A credential with no business attached
# buys nothing, and a business with no credential can't be measured — they
# are only useful together, and splitting them across two screens produces a
# setup that is half done more often than not.
#
# The credential is a login/password pair rather than a key, which is how
# DataForSEO issues them. Both go to the encrypted column and neither is ever
# sent back to the form; the page shows "set, ends in ab12" and nothing more.
class Settings::ReportingsController < Settings::BaseController
  include PluginGated
  plugin :local_marketing

  requires_capability "settings:read",  only: [:show]
  requires_capability "settings:write", only: [:update]

  SETTING_KEY = "reporting"

  def show
    login = Setting.secret(SETTING_KEY, :dataforseo_login).to_s
    @login_hint = login[-4..] if login.present?
    @password_set = Setting.secret(SETTING_KEY, :dataforseo_password).present?
    @sandbox = Setting.get(SETTING_KEY)["sandbox"].present?
    @profile = Reports::Profile.load
    @configured = DataForSeo::Client.configured?
  end

  def update
    Reports::Profile.change(settings_params)
    redirect_to settings_reporting_path, notice: "Reporting settings saved"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_reporting_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def settings_params
    params.require(:settings).permit(
      :dataforseo_login, :dataforseo_password, :sandbox,
      :business_name, :place_id, :cid,
      :location_name, :location_code, :country_name, :language_code, :domain,
      :brand_terms, :tracked_keywords, :competitors, :audit_urls,
      :map_grid_size, :map_spacing_km, :map_keywords,
      :phone, :address, :citation_directories
    )
  end
end
