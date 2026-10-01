# frozen_string_literal: true

module WebhooksHelper
  WEBHOOK_EVENT_GROUPS = {"Pages" => "page.", "Collection entries" => "entry.", "Globals" => "global."}.freeze

  # [["Pages", ["page.published", …]], …], the events grouped the way the form
  # shows them: the core's, then those of plugins that are on.
  def webhook_event_groups
    core = WEBHOOK_EVENT_GROUPS.filter_map do |label, prefixes|
      events = Webhook::EVENTS.select { |event| Array(prefixes).any? { event.start_with?(it) } }
      [label, events] if events.any?
    end
    core + Cms::Plugins.enabled_webhook_event_groups
  end

  def webhook_health(webhook)
    if !webhook.active
      status_tag "Inactive"
    elsif webhook.last_status.blank?
      status_tag "No deliveries yet"
    elsif webhook.last_status == "success"
      status_tag "Delivering", highlight: true
    else
      tag.span "Failing (#{webhook.failure_count})", class: "status-tag status-tag--negative border-radius pad-inline-half txt-x-small txt-uppercase font-weight-bold txt-nowrap"
    end
  end
end
