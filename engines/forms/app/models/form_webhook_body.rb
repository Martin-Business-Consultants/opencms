# frozen_string_literal: true

# What a form's own webhook posts (forms.webhook_body), after Gravity Forms'
# Webhooks: "all" (the default) sends the whole submission as it always has;
# "fields" sends only the keys the editor mapped, each to a field's value, a
# detail of the submission, or a custom value that may carry {{tokens}}
# (FormTokens):
#
#   {"mode" => "fields", "mappings" => [
#     {"key" => "email_address", "source" => "field:email"},
#     {"key" => "submitted",     "source" => "meta:submitted_at"},
#     {"key" => "lead_source",   "source" => "custom", "value" => "Website: {{form_title}}"}
#   ]}
#
# The webhook sheet posts rows as form[webhook_body][mappings][<row id>][…],
# read back in order; a row without a key is dropped.
class FormWebhookBody
  MODES = %w[all fields].freeze

  # The submission's own details a key can take, as the sheet labels them.
  META = {
    "submission_id" => "Submission ID",
    "submitted_at"  => "Submitted at",
    "ip"            => "IP address",
    "form_title"    => "Form title",
    "form_slug"     => "Form slug"
  }.freeze

  class << self
    def from_params(raw)
      raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      mode = MODES.include?(raw["mode"]) ? raw["mode"] : "all"
      rows = raw["mappings"].respond_to?(:to_unsafe_h) ? raw["mappings"].to_unsafe_h : raw["mappings"].to_h
      mappings = rows.values.filter_map { |row| mapping_from(row.to_h.stringify_keys) if row.respond_to?(:to_h) }
      {"mode" => mode, "mappings" => mappings}
    end

    private

    def mapping_from(row)
      key = row["key"].to_s.strip
      return nil if key.empty?

      source = row["source"].to_s
      if source == "custom"
        {"key" => key, "source" => "custom", "value" => row["value"].to_s}
      else
        {"key" => key, "source" => source}
      end
    end
  end

  def initialize(form)
    @form = form
    body = form.webhook_body.is_a?(Hash) ? form.webhook_body : {}
    @mode = MODES.include?(body["mode"]) ? body["mode"] : "all"
    @mappings = Array(body["mappings"]).select { it.is_a?(Hash) && it["key"].present? }
  end

  attr_reader :mode, :mappings

  def mapped? = mode == "fields"

  # The mapped keys and their values for a submission.
  def payload(submission)
    data = submission.data.is_a?(Hash) ? submission.data : {}
    mappings.to_h { |mapping| [mapping["key"], value(mapping, submission, data)] }
  end

  private

  def value(mapping, submission, data)
    kind, name = mapping["source"].to_s.split(":", 2)
    case kind
    when "field" then data[name]
    when "meta" then meta(name, submission)
    when "custom" then FormTokens.render(@form, mapping["value"], submission)
    end
  end

  def meta(name, submission)
    case name
    when "submission_id" then submission.id
    when "submitted_at"  then submission.created_at&.iso8601
    when "ip"            then submission.ip
    when "form_title"    then @form.title
    when "form_slug"     then @form.slug
    end
  end
end
