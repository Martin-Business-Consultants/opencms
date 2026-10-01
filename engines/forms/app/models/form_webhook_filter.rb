# frozen_string_literal: true

# A webhook's criteria for submission.created: `{"form_slugs" => [...]}`
# narrows its deliveries to the chosen forms; no slugs means every form.
# Registered with Cms::Plugins.webhook_event_filter, so the core's Webhook
# stores, validates and applies it without knowing what a form is.
module FormWebhookFilter
  EVENT = "submission.created"

  module_function

  # The stored shape from submitted params, or nil for "every form".
  def permit(raw)
    return nil unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

    slugs = Array(raw["form_slugs"]).map(&:to_s).reject(&:empty?)
    slugs.any? ? {"form_slugs" => slugs} : nil
  end

  def validate(value, errors)
    unless value.is_a?(Hash)
      errors.add(:event_filters, "#{EVENT} filter must be an object")
      return
    end

    slugs = value["form_slugs"]
    if slugs && !(slugs.is_a?(Array) && slugs.all? { it.is_a?(String) })
      errors.add(:event_filters, "#{EVENT} form_slugs must be an array of strings")
    end
  end

  def match(value, payload)
    slugs = Array(value.is_a?(Hash) ? value["form_slugs"] : nil)
    return true if slugs.empty?

    slug = payload.is_a?(Hash) ? (payload["form_slug"] || payload[:form_slug]).to_s : ""
    slugs.include?(slug)
  end
end
