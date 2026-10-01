# frozen_string_literal: true

# Asks the site to rebuild through the configured provider (Deploys).
class Deploys::TriggerJob < ApplicationJob
  queue_as :default

  # `_tenant` is only for jobs queued before this app became a single install;
  # it's ignored. Drop it once those have drained.
  def perform(scheduled_at, reason, _tenant = nil) = Deploys.trigger_now(scheduled_at, reason)
end
