# frozen_string_literal: true

# Settings → Commerce. Who is told about quote requests, and how invoices are
# numbered and signed. Read by QuoteRequest notifications, Invoice numbering,
# the invoice mailer and the hosted invoice page.
class Settings::CommercesController < Settings::BaseController
  include PluginGated
  plugin :commerce

  requires_capability "invoices:read",  only: :show
  requires_capability "invoices:write", only: :update

  SETTING_KEY = "commerce"
  FIELDS = %w[
    notification_recipients from_name from_email reply_to success_message
    business_name business_address business_phone
    invoice_prefix invoice_next_number currency due_days default_terms
  ].freeze

  def show
    data = Setting.get(SETTING_KEY)
    @settings = FIELDS.index_with { |f| data[f].to_s }
    @quote_endpoint = "#{request.base_url}/api/quote_requests"
    @next_number = Invoice.next_number
  end

  def update
    incoming = settings_params.to_h.transform_values { |v| v.to_s.strip }
    incoming["invoice_prefix"] = incoming["invoice_prefix"].upcase.gsub(/[^A-Z0-9]/, "") if incoming.key?("invoice_prefix")
    incoming["currency"]       = incoming["currency"].upcase[0, 3] if incoming.key?("currency")

    Setting.set(SETTING_KEY, incoming)
    Event.record("settings.commerce_updated", fields: incoming.keys)
    redirect_to settings_commerce_path, notice: "Commerce settings saved"
  end

  private

  def settings_params
    params.require(:settings).permit(*FIELDS)
  end
end
