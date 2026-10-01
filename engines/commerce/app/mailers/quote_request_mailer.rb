# frozen_string_literal: true

# "Someone wants a price": the shop's copy of a quote request.
class QuoteRequestMailer < ApplicationMailer
  def notification
    @quote      = params[:quote_request]
    settings    = Setting.get("commerce")
    from_name   = settings["from_name"].presence || Setting.get("general")["title"].presence || "Quotes"
    from_email  = settings["from_email"].presence || ApplicationMailer.from_address

    mail(
      from:     "\"#{from_name}\" <#{from_email}>",
      to:       params[:recipients],
      reply_to: @quote.customer_email.presence,
      subject:  "Quote request ##{@quote.id}: #{@quote.summary}"
    )
  end
end
