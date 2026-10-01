# frozen_string_literal: true

# Updates a Docker install by starting the releases repo's Deploy workflow
# for the release's tag (.github/workflows/deploy.yml), which runs
# `bin/kamal deploy -d <destination>` with the secrets kept in the matching
# GitHub environment. The new container backs up the data directory and
# migrates on boot; this install then runs the new version, which settles the
# upgrade.
#
#   CMS_DEPLOY_WORKFLOW     the workflow file (default deploy.yml)
#   CMS_DEPLOY_DESTINATION  the Kamal destination (config/deploy.<name>.yml).
#                           Required: config/deploy.yml has require_destination.
class Upgrade::Github
  def self.workflow = ENV["CMS_DEPLOY_WORKFLOW"].presence || "deploy.yml"
  def self.destination = ENV["CMS_DEPLOY_DESTINATION"].to_s.strip

  def self.unavailable_reason
    if !UpdateCheck::Github.deploy_token?
      "Set CMS_GITHUB_TOKEN (Actions read and write on #{UpdateCheck.repo}) to start the Deploy workflow from here."
    elsif destination.blank?
      "Set CMS_DEPLOY_DESTINATION to this install's Kamal destination (config/deploy.<name>.yml): every deploy needs one."
    end
  end

  def initialize(upgrade)
    @upgrade = upgrade
  end

  def start
    run = api.post("actions/workflows/#{self.class.workflow}/dispatches", ref: @upgrade.tag, return_run_details: true,
      inputs: {version: @upgrade.tag, destination: self.class.destination, upgrade: marker})
    remember run["workflow_run_id"], run["html_url"] if run["workflow_run_id"]
  end

  # Fails the upgrade when its run finished without deploying. A run that
  # succeeded is left for the new version's boot to settle.
  def check
    find_run unless @upgrade.external_id
    if @upgrade.external_id
      run = api.get("actions/runs/#{@upgrade.external_id}")
      if run["status"] == "completed" && run["conclusion"] != "success"
        @upgrade.fail_with "The deploy on GitHub ended #{run["conclusion"].to_s.tr("_", " ")}. Its log says why."
      end
    end
  end

  # A run that hasn't settled within Upgrade::TIMEOUT of the ask has gone quiet.
  def timing_out_since = @upgrade.created_at

  def where_to_look = "The deploy's log on GitHub says what happened."

  private

  def api = UpdateCheck::Github.new

  # Names this install and upgrade in the run's title, so the run can be
  # found again when GitHub doesn't return its id: other installs deploy
  # from the same workflow.
  def marker = "#{Site.host.presence || "localhost"} ##{@upgrade.id}"

  def find_run
    runs = api.get("actions/workflows/#{self.class.workflow}/runs", event: "workflow_dispatch",
      created: ">=#{(@upgrade.created_at - 1.minute).utc.iso8601}")["workflow_runs"].to_a
    run = runs.find { it["display_title"].to_s.include?("(#{marker})") }
    remember run["id"], run["html_url"] if run
  end

  def remember(id, url)
    @upgrade.update!(external_id: id.to_s, external_url: url)
  end
end
