# frozen_string_literal: true

# Read straight from UpdateCheck and Upgrade, so GET /api/updates and
# POST /api/updates/check answer in one shape.
json.version Cms::VERSION
json.update_available UpdateCheck.update_available?
json.latest_release do
  if UpdateCheck.latest_version
    json.version UpdateCheck.latest_version
    json.url UpdateCheck.release_url
    json.published_at UpdateCheck.published_at
    json.notes UpdateCheck.notes
  else
    json.nil!
  end
end
json.checked_at UpdateCheck.checked_at
json.daily_check UpdateCheck.checking?
json.updates_by Upgrade.via
json.not_set_up_because Upgrade.unavailable_reason
json.past_updates Upgrade.ordered.includes(:requested_by).limit(10) do |upgrade|
  json.extract! upgrade, :id, :from_version, :to_version, :status, :via
  json.requested_by upgrade.requested_by&.name
  json.started_at upgrade.created_at
  json.finished_at upgrade.finished_at
  json.log_url upgrade.external_url
  json.message upgrade.message
end
