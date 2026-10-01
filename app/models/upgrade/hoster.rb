# frozen_string_literal: true

require "net/http"
require "json"

# Updates an install Hoster deploys by asking Hoster to deploy the release's
# tag to this install's environment. Hoster's API only proposes: the ask is a
# change request a person approves in Hoster, after which Hoster runs the
# deploy. The new container backs up the data directory and migrates on boot;
# this install then runs the new version, which settles the upgrade.
#
#   CMS_HOSTER_URL             where Hoster is (https://hoster.example.com)
#   CMS_HOSTER_TOKEN           a Hoster API token with write access (it may propose)
#   CMS_HOSTER_ENVIRONMENT_ID  this install's environment in Hoster
#
# external_id is "change_request:<id>" until Hoster applies it, then
# "deployment:<id>", so a check knows which of the two to read.
class Upgrade::Hoster
  class Error < UpdateCheck::Github::Error; end

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15

  def self.url = ENV["CMS_HOSTER_URL"].to_s.strip.delete_suffix("/")
  def self.token = ENV["CMS_HOSTER_TOKEN"].presence
  def self.environment_id = ENV["CMS_HOSTER_ENVIRONMENT_ID"].to_s.strip

  def self.configured? = token.present?

  def self.unavailable_reason
    if token.blank?
      "Set CMS_HOSTER_TOKEN (a Hoster API token with write access) to ask Hoster for the deploy."
    elsif url.blank?
      "Set CMS_HOSTER_URL to where Hoster is."
    elsif environment_id.blank?
      "Set CMS_HOSTER_ENVIRONMENT_ID to this install's environment in Hoster."
    end
  end

  def initialize(upgrade)
    @upgrade = upgrade
  end

  def start
    change = post("change_requests", action_name: "environments.deploy",
      params: {environment_id: self.class.environment_id, ref: @upgrade.tag})["change_request"]
    remember "change_request", change
  end

  # Follows the change request until Hoster applies it, then the deployment
  # it started. A deployment that succeeded is left for the new version's
  # boot to settle.
  def check
    kind, id = @upgrade.external_id.to_s.split(":", 2)
    case kind
    when "change_request" then check_change_request(id)
    when "deployment" then check_deployment(id)
    end
  end

  # Waiting for a person in Hoster isn't the deploy going quiet, so the clock
  # starts once the deploy does.
  def timing_out_since = awaiting_approval? ? nil : @upgrade.updated_at

  def awaiting_approval? = @upgrade.external_id.to_s.start_with?("change_request:")

  def where_to_look = "Hoster's page for the deploy says what happened."

  private

  def check_change_request(id)
    change = get("change_requests/#{id}")["change_request"]
    case change["status"]
    when "rejected"
      @upgrade.fail_with "The deploy was turned down in Hoster#{" by #{change["decided_by"]}" if change["decided_by"]}."
    when "failed"
      @upgrade.fail_with "Hoster couldn't start the deploy: #{change["error"].presence || "its change request failed"}."
    when "applied"
      deployment_id = change.dig("result", "deployment_id")
      deployment = get("deployments/#{deployment_id}")["deployment"] if deployment_id
      deployment ? remember("deployment", deployment) : @upgrade.fail_with("Hoster applied the change but started no deploy.")
    end
  end

  def check_deployment(id)
    deployment = get("deployments/#{id}")["deployment"]
    if %w[failed cancelled].include?(deployment["status"])
      @upgrade.fail_with "The deploy in Hoster #{deployment["status"]}#{": #{deployment["error"]}" if deployment["error"].present?}."
    end
  end

  def remember(kind, record)
    @upgrade.update!(external_id: "#{kind}:#{record.fetch("id")}", external_url: record["url"])
  end

  def get(path) = request(Net::HTTP::Get.new(uri_for(path)))

  def post(path, body)
    request Net::HTTP::Post.new(uri_for(path)).tap { it.body = body.to_json; it["Content-Type"] = "application/json" }
  end

  def uri_for(path) = URI("#{self.class.url}/api/v1/#{path}")

  def request(request)
    request["Accept"] = "application/json"
    request["User-Agent"] = "cms/#{Cms::VERSION}"
    request["Authorization"] = "Bearer #{self.class.token}"

    response = http_for(request.uri).request(request)
    raise Error, failure(response) unless response.is_a?(Net::HTTPSuccess)

    response.body.present? ? JSON.parse(response.body) : {}
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => error
    raise Error, "Couldn't reach Hoster at #{self.class.url} (#{error.message})."
  end

  def http_for(uri)
    Net::HTTP.new(uri.host, uri.port).tap do |http|
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
    end
  end

  def failure(response)
    message = begin
      JSON.parse(response.body.to_s)["error"]
    rescue JSON::ParserError, TypeError
      nil
    end

    case response.code.to_i
    when 401 then "Hoster refused CMS_HOSTER_TOKEN: it's wrong or has been revoked."
    when 403 then "Hoster refused: #{message || "the token can't propose changes"}."
    when 404 then "Hoster has no environment #{self.class.environment_id} (or record) this token can see."
    else "Hoster answered #{response.code}#{": #{message}" if message}."
    end
  end
end
