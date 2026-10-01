# frozen_string_literal: true

# Whether a newer CMS release exists: the latest published GitHub release of
# the CMS repo (CMS_RELEASES_REPO, default the repo this install came from;
# drafts and prereleases left out), checked daily by UpdateCheckJob and from
# Settings › Updates, and kept in the "updates" setting so a page never waits
# on GitHub. Installing it is an Upgrade.
#
#   UpdateCheck.check_now         # fetch and store; quiet on network failure
#   UpdateCheck.check_now!        # the same, raising UpdateCheck::Github::Error ("Check now")
#   UpdateCheck.latest_version    # "1.2.0" or nil
#   UpdateCheck.update_available?
module UpdateCheck
  SETTING_KEY  = "updates"
  DEFAULT_REPO = "Martin-Business-Consultants/opencms"

  module_function

  def repo = ENV["CMS_RELEASES_REPO"].presence || DEFAULT_REPO

  # Off with CMS_UPDATE_CHECK=false: an install with no way out to GitHub.
  def checking? = ENV["CMS_UPDATE_CHECK"] != "false"

  def check_later = UpdateCheckJob.perform_later

  def check_now
    check_now!
  rescue StandardError => e
    Rails.logger.warn("[update_check] #{e.class}: #{e.message}")
    nil
  end

  def check_now!
    release = Github.new.get("releases/latest")

    Setting.set(SETTING_KEY, {
      "latest_version" => release["tag_name"].to_s.delete_prefix("v"),
      "release_url"    => release["html_url"],
      "notes"          => release["body"],
      "published_at"   => release["published_at"],
      "checked_at"     => Time.current.iso8601
    })
  end

  def latest_version = stored["latest_version"].presence
  def latest_tag = latest_version&.then { "v#{it}" }
  def release_url = stored["release_url"].presence
  def notes = stored["notes"].presence
  def published_at = parse_time(stored["published_at"])
  def checked_at = parse_time(stored["checked_at"])

  def update_available?
    latest = latest_version or return false
    Gem::Version.new(latest) > Cms.version
  rescue ArgumentError
    false
  end

  def changelog_url = "https://github.com/#{repo}/blob/main/CHANGELOG.md"

  def stored = Setting.get(SETTING_KEY)
  private_class_method :stored

  def parse_time(value) = value.presence&.then { Time.zone.parse(it.to_s) }
  private_class_method :parse_time
end
