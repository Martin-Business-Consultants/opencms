# frozen_string_literal: true

# One update of this install to a newer release, started by an admin from
# Settings › Updates. How it happens depends on how the install runs
# (`Upgrade.via`):
#
#   hoster  an install Hoster deploys: proposes the release's deploy to
#           Hoster, which a person approves there (Upgrade::Hoster)
#   github  a Docker install deployed with Kamal: starts the releases repo's
#           Deploy workflow (.github/workflows/deploy.yml) for this install's
#           destination (Upgrade::Github)
#   local   a plain install (bin/install): runs bin/update with the release's
#           tag in the background, which restarts Puma when it's done
#           (Upgrade::Local)
#   manual  neither is set up: Settings › Updates shows the command instead
#
# CMS_UPDATES picks one. Left unset, a production checkout with a .env is
# local, one with CMS_HOSTER_TOKEN is hoster, and one with CMS_GITHUB_TOKEN
# is github; anything
# else, development included, is manual, so a button never checks out a tag
# over someone's working copy. It succeeds when this install boots on the new
# version; a failed run, or no word within TIMEOUT, fails it. The old version
# keeps running meanwhile.
class Upgrade < ApplicationRecord
  include Eventable

  class Refused < StandardError; end

  VIAS = %w[hoster github local manual].freeze
  STATUSES = %w[running succeeded failed].freeze
  TIMEOUT = 45.minutes

  # Optional only so deleting the person keeps the record of what they did.
  belongs_to :requested_by, class_name: "User", optional: true

  validates :requested_by, presence: true, on: :create
  validates :via, inclusion: {in: VIAS - %w[manual]}
  validates :status, inclusion: {in: STATUSES}

  scope :running, -> { where(status: "running") }
  scope :ordered, -> { order(created_at: :desc, id: :desc) }

  def self.via
    configured = ENV["CMS_UPDATES"].presence
    if VIAS.include?(configured)
      configured
    elsif !Rails.env.production?
      "manual"
    elsif Rails.root.join(".git").exist? && Rails.root.join(".env").exist?
      "local"
    elsif Upgrade::Hoster.configured?
      "hoster"
    elsif UpdateCheck::Github.deploy_token?
      "github"
    else
      "manual"
    end
  end

  # Why the button can't update this install, or nil when it can.
  def self.unavailable_reason
    case via
    when "local" then nil
    when "hoster" then Upgrade::Hoster.unavailable_reason
    when "github" then Upgrade::Github.unavailable_reason
    else "Updating from here isn't set up on this install."
    end
  end

  def self.available? = unavailable_reason.nil?

  def self.current = running.ordered.first

  # Updates the install to the latest release, as the person who asked.
  # Refuses when that release isn't newer, updating isn't set up, or an
  # update is already running.
  def self.start(by:)
    raise Refused, unavailable_reason unless available?
    raise Refused, "There's no newer release to update to." unless UpdateCheck.update_available?
    raise Refused, "An update to #{current.to_version} is already running." if current

    create!(requested_by: by, from_version: Cms::VERSION, to_version: UpdateCheck.latest_version, via: via).tap do |upgrade|
      upgrade.track_event(:started, from_version: upgrade.from_version, to_version: upgrade.to_version, via: upgrade.via)
      upgrade.run
    end
  end

  # Settles running updates: done once this install runs the new version,
  # failed when the run failed or went quiet. Called by Settings › Updates
  # and the daily check.
  def self.settle_running = running.find_each(&:settle)

  def run
    runner.start
  rescue UpdateCheck::Github::Error, SystemCallError => error
    fail_with error.message
  end

  def settle
    if Cms.version >= Gem::Version.new(to_version)
      update!(status: "succeeded", finished_at: Time.current, message: nil)
    elsif (since = runner.timing_out_since) && since < TIMEOUT.ago
      fail_with "No word after #{TIMEOUT.inspect}. #{runner.where_to_look}"
    else
      runner.check
    end
  rescue UpdateCheck::Github::Error => error
    Rails.error.report(error, context: {upgrade: id})
  end

  def fail_with(message)
    update!(status: "failed", finished_at: Time.current, message: message)
  end

  def running? = status == "running"
  def succeeded? = status == "succeeded"
  def failed? = status == "failed"

  def tag = "v#{to_version}"

  # How the audit log names it.
  def title = "#{from_version} → #{to_version}"

  def runner = {"hoster" => Upgrade::Hoster, "github" => Upgrade::Github, "local" => Upgrade::Local}.fetch(via).new(self)
end
