# frozen_string_literal: true

# Runs once a minute, flipping any pages or collection entries
# whose scheduled publish/unpublish time has arrived. Status changes go
# through `update!` so existing webhooks (page.published, page.unpublished,
# entry.published, entry.unpublished) fire automatically.
#
# Idempotent: an already-published page with a past publish_at simply
# doesn't match the scope, so re-running is safe.
class ProcessScheduledPublishingJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    process_pages(now)
    process_entries(now)
  end

  private

  def process_pages(now)
    Page.publish_due(now)
    Page.unpublish_due(now)
  end

  def process_entries(now)
    CollectionEntry.publish_due(now)
    CollectionEntry.unpublish_due(now)
  end
end
