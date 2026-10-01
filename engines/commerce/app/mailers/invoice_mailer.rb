# frozen_string_literal: true

# The customer's copy of an invoice: totals, the hosted page, and the payment
# link. Business identity (name, address, reply-to) comes from the commerce
# Setting so the mail reads as the shop, not as the CMS.
class InvoiceMailer < ApplicationMailer
  def deliver
    @invoice   = params[:invoice]
    @settings  = Setting.get("commerce")
    @business  = @settings["business_name"].presence || Setting.get("general")["title"].presence || "Invoice"
    @view_url  = "#{params[:base_url].to_s.sub(%r{/+\z}, "")}#{@invoice.public_path}"
    from_email = @settings["from_email"].presence || ApplicationMailer.from_address

    mail(
      from:     "\"#{@business}\" <#{from_email}>",
      to:       @invoice.customer_email,
      reply_to: @settings["reply_to"].presence,
      subject:  "Invoice #{@invoice.number} from #{@business} — #{@invoice.formatted(@invoice.total_cents)}"
    )
  end
end
