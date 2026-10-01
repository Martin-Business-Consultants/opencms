# frozen_string_literal: true

# The hook URL can carry a secret in its path, so only its host is shown;
# `url_set` is what a caller needs to know before triggering.
settings = Deploys.config
host = begin
  URI.parse(settings["url"].to_s).host if settings["url"].to_s.strip.present?
rescue URI::InvalidURIError
  nil
end

json.url_set settings["url"].to_s.length.positive?
json.url_host host
json.paused settings["paused"] == true
json.scheduled_at settings["scheduled_at"]
json.last_status settings["last_status"]
json.last_fired_at settings["last_fired_at"]
json.last_reason settings["last_reason"]
json.log Array(settings["log"])
