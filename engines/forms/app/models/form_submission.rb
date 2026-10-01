# frozen_string_literal: true

# An inbound submission against a Form. `data` holds the form field values
# keyed by field name. File-typed fields are stored as Active Storage
# attachments under `files`; the data hash lists their attachment blob ids
# under the field name so the form definition still maps cleanly to inputs.
class FormSubmission < ApplicationRecord
  include ListSearchable

  search_on :data

  include Eventable
  include Notifiable

  # Its events have always been "submission.…".
  def self.eventable_prefix = "submission"

  belongs_to :form
  has_many_attached :files

  validates :data, presence: true

  after_create_commit :enqueue_notifications
  after_create_commit :emit_submission_webhook

  def webhook_payload
    {
      id:            id,
      form_slug:     form.slug,
      form_title:    form.title,
      data:          data,
      meta:          meta,
      ip:            ip,
      file_count:    files.attached? ? files.count : 0,
      created_at:    created_at&.iso8601
    }
  end

  private

  def enqueue_notifications
    has_email   = form.emails.enabled.exists?
    has_webhook = form.notify_webhook_url.present?
    return unless has_email || has_webhook

    notify_later
  end

  # Fans the submission out to any Webhook subscribed to `submission.created`.
  # Independent of the per-Form notify_webhook_url path above; that one is a
  # single hard-coded endpoint per form, this is the editor-managed Webhook
  # resource that any number of consumers can subscribe to.
  def emit_submission_webhook
    announce("submission.created")
  end
end
