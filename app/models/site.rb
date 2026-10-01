# frozen_string_literal: true

# The one site this install serves. An install is one customer's CMS: its
# own process, database and data directory, reached at APP_HOST.
#
#   Site.host  # => "acme.librepublish.com"  (APP_HOST)
#   Site.key   # => "acme"                   (SITE_KEY, else the host's first label)
#
# `key` is what the API has always sent as `tenant` (manifest, webhook
# envelopes, device login's `account`) and what Lumin matches a site on, so
# it has to stay the same when an install moves hosts.
module Site
  module_function

  def host
    Rails.configuration.x.app_host.to_s
  end

  def key
    Rails.configuration.x.site_key.presence || host.split(":").first.to_s.split(".").first.to_s
  end

  # The site's own time zone (Settings › General), which the admin shows and
  # reads every time in. Stored times stay UTC. Falls back to the server's
  # zone when unset or unknown.
  def time_zone
    name = Setting.get("general")["timezone"].presence
    (name && Time.find_zone(name)) || server_time_zone
  rescue ActiveRecord::ActiveRecordError
    server_time_zone
  end

  def server_time_zone
    Time.find_zone(ENV["TZ"].presence || system_zone_name.to_s) || Time.find_zone("UTC")
  end

  # The system zone's IANA name, from /etc/localtime's link (".../zoneinfo/America/New_York").
  def system_zone_name
    File.readlink("/etc/localtime").split("zoneinfo/").last
  rescue SystemCallError
    nil
  end

  # For links built outside a request (mailers, jobs, the CLI bootstrap).
  def url_options
    name, port = host.split(":", 2)
    {host: name, port: port&.to_i, protocol: Rails.configuration.x.app_protocol}.compact
  end
end
