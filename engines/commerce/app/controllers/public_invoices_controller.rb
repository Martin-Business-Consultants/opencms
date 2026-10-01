# frozen_string_literal: true

# The customer's view of an invoice, reached from the email by an unguessable
# token. Plain HTML, printable, no sign-in: the person paying is not a user.
class PublicInvoicesController < ApplicationController
  include PluginGated
  plugin :commerce

  layout "invoice"
  skip_authorization
  skip_before_action :authenticate, raise: false

  def show
    @invoice  = Invoice.find_by!(token: params[:token])
    @settings = Setting.get("commerce")
    @business = @settings["business_name"].presence || Setting.get("general")["title"].presence || "Invoice"
    @logo_url = logo_url
  end

  private

  def logo_url
    logo_id = Setting.get("branding")["logo_id"]
    return nil if logo_id.blank?

    asset = Asset.with_attached_file.find_by(id: logo_id)
    return nil unless asset&.file&.attached?

    Rails.application.routes.url_helpers.rails_blob_path(asset.file, only_path: true)
  rescue StandardError
    nil
  end
end
