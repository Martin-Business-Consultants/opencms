# frozen_string_literal: true

# Telling the shop a quote request came in: an email to the recipients in
# Settings › Commerce, when there are any.
module QuoteRequest::Notifiable
  extend ActiveSupport::Concern

  def notify_later
    QuoteRequest::NotificationJob.perform_later(id)
  end

  def notify_now
    recipients = Setting.get("commerce")["notification_recipients"].to_s
      .split(/[,\n]/).map(&:strip).reject(&:empty?)
    return if recipients.empty?

    QuoteRequestMailer.with(quote_request: self, recipients: recipients).notification.deliver_now
  end
end
