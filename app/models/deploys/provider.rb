# frozen_string_literal: true

# The interface a deploy provider implements (see Deploys). `config` is the
# deploy setting's hash; a provider reads whatever else it needs (Settings ›
# GitHub, its own plugin settings) itself.
class Deploys::Provider
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  def self.key = name.demodulize.underscore
  def self.label = name.demodulize.titleize

  attr_reader :config

  def initialize(config = {})
    @config = config
  end

  def key = self.class.key
  def label = self.class.label

  # Whether a build can be fired at all.
  def configured?
    raise NotImplementedError
  end

  # Where builds go, for Settings and the API: a host, a repo.
  def target
    nil
  end

  # Fires one build. Returns a Deploys::Attempt; never raises for a network
  # or HTTP failure, which is a "failure" attempt in the log.
  def fire(reason:)
    raise NotImplementedError
  end

  private

  def attempt_from(response, error)
    Deploys::Attempt.new(
      status:      response.is_a?(Net::HTTPSuccess) ? "success" : "failure",
      http_status: response&.code&.to_i,
      error:       error
    )
  end
end
