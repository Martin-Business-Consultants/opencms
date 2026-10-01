# frozen_string_literal: true

require "net/http"
require "json"

# The few calls updating makes to GitHub's REST API, on the CMS's releases
# repository: its latest release, and for a Docker install that updates
# through GitHub Actions, starting and following the Deploy workflow.
#
#   CMS_RELEASES_REPO    where releases are published (owner/name)
#   CMS_GITHUB_TOKEN     starts a deploy (a fine-grained token: Actions read
#                        and write); also used to read releases
#   CMS_RELEASES_TOKEN   reads releases only, for a private repository
#
# A public repository's releases need no token at all.
class UpdateCheck::Github
  class Error < StandardError; end

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15

  def self.token = ENV["CMS_GITHUB_TOKEN"].presence || ENV["CMS_RELEASES_TOKEN"].presence

  # Only CMS_GITHUB_TOKEN can start a deploy: CMS_RELEASES_TOKEN is read-only by intent.
  def self.deploy_token? = ENV["CMS_GITHUB_TOKEN"].present?

  def get(path, params = {})
    uri = uri_for(path)
    uri.query = URI.encode_www_form(params) if params.any?
    request Net::HTTP::Get.new(uri)
  end

  def post(path, body)
    request Net::HTTP::Post.new(uri_for(path)).tap { it.body = body.to_json; it["Content-Type"] = "application/json" }
  end

  private

  def uri_for(path) = URI("https://api.github.com/repos/#{UpdateCheck.repo}/#{path}")

  def request(request)
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["User-Agent"] = "cms/#{Cms::VERSION}"
    request["Authorization"] = "Bearer #{self.class.token}" if self.class.token

    response = http_for(request.uri).request(request)
    raise Error, failure(response) unless response.is_a?(Net::HTTPSuccess)

    response.body.present? ? JSON.parse(response.body) : {}
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => error
    raise Error, "Couldn't reach GitHub (#{error.message})."
  end

  def http_for(uri)
    Net::HTTP.new(uri.host, uri.port).tap do |http|
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
    end
  end

  def failure(response)
    message = begin
      JSON.parse(response.body.to_s)["message"]
    rescue JSON::ParserError, TypeError
      nil
    end

    case response.code.to_i
    when 401
      self.class.token ? "GitHub refused the token: it's wrong or has expired." : "GitHub needs CMS_GITHUB_TOKEN for that."
    when 403
      "GitHub refused: #{message || "the token lacks access"}."
    when 404
      "GitHub has no releases or workflow for #{UpdateCheck.repo} that this install can see" \
        "#{" (a private repository needs CMS_RELEASES_TOKEN or CMS_GITHUB_TOKEN)" unless self.class.token}."
    else
      "GitHub answered #{response.code}#{": #{message}" if message}."
    end
  end
end
