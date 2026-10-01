# frozen_string_literal: true

require "net/http"
require "json"

# A `repository_dispatch` on the site's repo (Settings › GitHub: the token and
# `frontend_github_repo`). The site's workflow starts a build on it:
#
#   on:
#     repository_dispatch:
#       types: [cms-publish]
#
# GitHub answers 204 for a dispatch it accepted.
class Deploys::Github < Deploys::Provider
  EVENT_TYPE = "cms-publish"

  def self.label = "GitHub"

  def configured?
    repo.present? && token.present?
  end

  def target = repo.presence

  def fire(reason:)
    uri  = URI("https://api.github.com/repos/#{repo}/dispatches")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    request = Net::HTTP::Post.new(uri.request_uri, {
      "Authorization"        => "Bearer #{token}",
      "Accept"               => "application/vnd.github+json",
      "X-GitHub-Api-Version" => "2022-11-28",
      "Content-Type"         => "application/json",
      "User-Agent"           => "mbc-cms-deploy/1"
    })
    request.body = JSON.generate(event_type: EVENT_TYPE, client_payload: {reason: reason, site: Site.key})
    attempt_from(http.request(request), nil)
  rescue StandardError => e
    attempt_from(nil, "#{e.class}: #{e.message}")
  end

  private

  def github = @github ||= Setting.get("github")
  def repo = github["frontend_github_repo"].to_s.strip
  def token = github["token"].to_s
end
