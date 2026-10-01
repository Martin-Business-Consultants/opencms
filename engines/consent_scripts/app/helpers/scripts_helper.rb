# frozen_string_literal: true

module ScriptsHelper
  SITE_STATUS_LABELS = {
    "on_site"       => "On the site",
    "hardcoded"     => "On the site (not via Scripts)",
    "not_served"    => "Not on the site",
    "not_injected"  => "Served but not loaded",
    "category_off"  => "Blocked by consent settings",
    "embed_missing" => "Can’t tell: embed missing",
    "banner_off"    => "Not served: banner off",
    "inactive"      => "Inactive",
    "unknown"       => "Not checked"
  }.freeze

  SITE_STATUS_TONES = {
    "on_site" => "positive", "hardcoded" => "positive",
    "not_served" => "negative", "not_injected" => "negative",
    "category_off" => "waiting", "embed_missing" => "waiting", "banner_off" => "waiting"
  }.freeze

  # The last site audit's verdict on one script, tinted by what it means.
  def script_site_status(script, audit)
    if script.active
      verdict = audit&.dig(:statuses, script.id.to_s) || {status: "unknown"}
      status  = verdict[:status].to_s
      label   = verdict[:label].presence || SITE_STATUS_LABELS.fetch(status, SITE_STATUS_LABELS["unknown"])
    else
      status, label = "inactive", SITE_STATUS_LABELS["inactive"]
    end
    tag.span label, class: "status-tag status-tag--#{SITE_STATUS_TONES.fetch(status, "neutral")} border-radius pad-inline-half txt-x-small font-weight-bold txt-nowrap"
  end

  # "3 active scripts not on the site", the audit's verdict in a line.
  def script_audit_verdict(scripts, audit)
    active    = scripts.select(&:active)
    status    = ->(s) { audit.dig(:statuses, s.id.to_s, :status).to_s }
    off_site  = active.count { |s| status.(s).in?(%w[not_served not_injected category_off]) }
    unchecked = active.count { |s| status.(s).in?(%w[embed_missing banner_off unknown]) || status.(s).empty? }

    if off_site.positive?
      "#{pluralize(off_site, "active script")} not on the site"
    elsif unchecked.positive?
      "#{pluralize(unchecked, "active script")} couldn’t be checked"
    else
      "every active script is on the site"
    end
  end

  # "googletagmanager.com · In <head>", or "inline", where a script comes from.
  def script_loads(script)
    source = script.src.present? ? (URI.parse(script.src).host rescue script.src) : "inline"
    source += " + inline" if script.src.present? && script.code.present?
    "#{source} · #{Script::PLACEMENT_LABELS[script.placement]}"
  end

  def script_category_options
    [["All categories", nil]] + Script::CATEGORIES.map { |c| [Script::CATEGORY_LABELS[c], c] }
  end
end
