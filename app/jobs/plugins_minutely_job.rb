# frozen_string_literal: true

# Every minute: each enabled plugin's minutely tasks that are due
# (Cms::Plugins.minutely). One task failing is logged and doesn't stop the
# others.
class PluginsMinutelyJob < ApplicationJob
  queue_as :default

  def perform(at: Time.current)
    Cms::Plugins.due_minutely_tasks(at).each do |name, task|
      task.call
    rescue StandardError => e
      Rails.logger.error("[plugins:minutely] #{name}: #{e.class}: #{e.message}")
    end
  end
end
