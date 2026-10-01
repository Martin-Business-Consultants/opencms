# frozen_string_literal: true

# Forms › Import: upserts forms (and their email templates) by slug from an
# export's JSON — a `{"forms": […]}` object or a bare array.
class Forms::ImportsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "forms:write", only: :create

  def create
    file = params[:file]
    return redirect_to(forms_path, alert: "Pick a JSON file to import.") unless file.respond_to?(:read)

    json = JSON.parse(file.read)
    rows = json.is_a?(Hash) ? Array(json["forms"]) : Array(json)
    created = updated = skipped = 0

    rows.each do |row|
      next unless row.is_a?(Hash) && row["slug"].is_a?(String)

      existing = Form.find_by(slug: row["slug"])
      attrs    = row.slice("title", "status", "fields", "submit_url", "submit_label", "success_message", "notify_webhook_url", "webhook_body")

      form = if existing
        existing.update!(attrs) ? (updated += 1) && existing : (skipped += 1; existing)
      else
        Form.create!(attrs.merge("slug" => row["slug"])).tap { created += 1 }
      end

      Array(row["emails"]).each do |email_row|
        next unless email_row.is_a?(Hash) && FormEmail::KINDS.include?(email_row["kind"])

        target = form.emails.find_or_initialize_by(kind: email_row["kind"])
        target.assign_attributes(email_row.slice("enabled", "subject", "body", "blocks", "from_field", "recipients"))
        target.save!
      end
    end

    Form.track_event(:imported, created: created, updated: updated, skipped: skipped)
    redirect_to forms_path,
      notice: "Import: #{created} created, #{updated} updated#{skipped.positive? ? ", #{skipped} skipped" : ""}."
  rescue JSON::ParserError => e
    redirect_to forms_path, alert: "Invalid JSON: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to forms_path, alert: "Import failed on #{e.record.try(:slug) || e.record.class.name}: #{e.record.errors.full_messages.join("; ")}"
  end
end
