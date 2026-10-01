# frozen_string_literal: true

require "net/http"

# Telling people a submission arrived: the form's enabled emails (the
# notification to the site's recipients, the confirmation to the submitter)
# and its own webhook URL, if it has one. Queued on create; the editor-managed
# Webhook resources hear about it through `submission.created` instead.
module FormSubmission::Notifiable
  extend ActiveSupport::Concern

  def notify_later
    FormSubmission::NotificationJob.perform_later(id)
  end

  def notify_now
    form.emails.enabled.find_each { |form_email| deliver_notification(form_email) }
    post_notification_webhook if form.notify_webhook_url.present?
  end

  private

  def deliver_notification(form_email)
    recipients = notification_recipients(form_email)
    return if recipients.empty?

    FormSubmissionMailer
      .with(form_email: form_email, submission: self, recipients: recipients)
      .deliver
      .deliver_now
  end

  def notification_recipients(form_email)
    if form_email.notification?
      form_email.recipient_list
    else
      Array(form_email.submitter_email_for(self))
    end
  end

  def post_notification_webhook
    uri = URI.parse(form.notify_webhook_url)
    body = FormWebhookBody.new(form)
    payload = body.mapped? ? body.payload(self) : {
      form: {slug: form.slug, title: form.title},
      submission: {
        id:         id,
        data:       data,
        meta:       meta,
        ip:         ip,
        files:      files.map { |f|
          {filename: f.filename.to_s, content_type: f.content_type, byte_size: f.byte_size, field: f.metadata["field"]}
        },
        created_at: created_at.iso8601
      }
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
    req.body = payload.to_json
    res = http.request(req)

    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[forms] webhook #{form.slug} -> #{uri} returned #{res.code}: #{res.body.to_s[0, 200]}")
    end
  end
end
