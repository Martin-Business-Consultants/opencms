# frozen_string_literal: true

# A per-form email template. Two kinds, one of each per form:
#   - "notification" — fired to admin recipient(s) on each new submission
#   - "confirmation" — auto-reply to the submitter, addressed to the email
#                      stored under `from_field` in the submission data
#
# Subject and body support {{field_name}} placeholder substitution against
# the submission's data hash, plus a few special tokens: {{form_title}},
# {{submission_id}}, {{submitted_at}}, {{ip}}.
class FormEmail < ApplicationRecord
  include Eventable
  include FormEmail::Content
  include FormEmail::SiteTemplate

  KINDS = %w[notification confirmation].freeze

  belongs_to :form

  validates :kind, inclusion: {in: KINDS}
  validates :kind, uniqueness: {scope: :form_id}
  validates :subject, presence: true, if: :enabled?
  validate  :validate_recipients

  scope :enabled, -> { where(enabled: true) }

  def notification?
    kind == "notification"
  end

  def confirmation?
    kind == "confirmation"
  end

  # Comma- or newline-separated admin recipients, parsed into an array.
  # Only meaningful for notification rows.
  def recipient_list
    recipients.to_s.split(/[,\n]/).map(&:strip).reject(&:empty?)
  end

  # Submitter's email for confirmation rows. Reads form data using
  # `from_field` if set, otherwise auto-detects the first field of type=email.
  def submitter_email_for(submission)
    return nil unless confirmation?

    name = from_field.presence || form.fields.find { |f| f.is_a?(Hash) && f["type"] == "email" }&.dig("name")
    return nil if name.blank?

    val = submission.data.is_a?(Hash) ? submission.data[name] : nil
    val.is_a?(String) && val.match?(URI::MailTo::EMAIL_REGEXP) ? val : nil
  end

  # Render `template` with {{token}} substitutions against the given
  # submission (FormTokens). Returns plain text — the view is responsible for
  # HTML escaping.
  def render(template, submission)
    FormTokens.render(form, template, submission)
  end

  private

  def validate_recipients
    return unless notification?
    return unless enabled?

    if recipient_list.empty?
      errors.add(:recipients, "must have at least one recipient when enabled")
    end
  end
end
