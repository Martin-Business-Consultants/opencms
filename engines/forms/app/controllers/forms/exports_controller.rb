# frozen_string_literal: true

# Forms › Export: every form and its two email templates as JSON, in the shape
# Forms::ImportsController reads back.
class Forms::ExportsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "forms:read", only: :show

  def show
    payload = {
      exported_at: Time.current.iso8601,
      tenant:      Site.key,
      forms:       Form.ordered.map { |form| export_payload(form) }
    }
    send_data JSON.pretty_generate(payload),
      filename: "forms-#{Site.key}-#{Time.current.strftime("%Y%m%d")}.json",
      type:     "application/json"
  end

  private

  def export_payload(form)
    form.as_json(only: %i[slug title status fields submit_url submit_label
      success_message notify_webhook_url webhook_body]).merge(
      "emails" => form.emails.order(:kind).map { |email|
        email.as_json(only: %i[kind enabled subject body blocks from_field recipients])
      }
    )
  end
end
