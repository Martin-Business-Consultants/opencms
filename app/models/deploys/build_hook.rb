# frozen_string_literal: true

require "net/http"

# A build-hook URL (Cloudflare Pages, Vercel, Netlify, any CI): an empty POST
# starts a build. The URL can carry a secret in its path, so only its host is
# ever shown.
class Deploys::BuildHook < Deploys::Provider
  def self.label = "Build hook"

  def configured?
    url.start_with?("http")
  end

  def target
    URI.parse(url).host if url.present?
  rescue URI::InvalidURIError
    nil
  end

  def fire(reason:)
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    request = Net::HTTP::Post.new(uri.request_uri, {"User-Agent" => "mbc-cms-deploy/1"})
    attempt_from(http.request(request), nil)
  rescue StandardError => e
    attempt_from(nil, "#{e.class}: #{e.message}")
  end

  private

  def url = config["url"].to_s
end
