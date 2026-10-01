# frozen_string_literal: true

# Runs every enabled plugin's nightly task (Cms::Plugins.nightly). One
# plugin failing is logged and doesn't stop the others.
class PluginsNightlyJob < ApplicationJob
  queue_as :default

  def perform
    Cms::Plugins.enabled_nightly_tasks.each do |key, task|
      task.call
    rescue StandardError => e
      Rails.logger.error("[plugins:nightly] #{key}: #{e.class}: #{e.message}")
    end
  end
end
