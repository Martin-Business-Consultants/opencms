# frozen_string_literal: true

# Who is emailed when a collection's entries move: the collection names the
# events and the recipients; Event.announce hands every entry announcement to
# CollectionEntry#notify_subscribers, which comes here.
module Collection::Notifying
  extend ActiveSupport::Concern

  # Subset of webhook events that an editor can opt into per-collection for
  # email notifications. Same vocabulary as Webhook::EVENTS, scoped to
  # entry.* — the only events relevant to collection content.
  NOTIFICATION_EVENTS = %w[entry.created entry.updated entry.published entry.unpublished entry.deleted].freeze

  # Parse the comma/newline-separated `notification_emails` blob into an
  # array of recipient addresses.
  def notification_email_list
    notification_emails.to_s.split(/[,\n]/).map(&:strip).reject(&:empty?)
  end

  # Should an entry-event email fire to the recipient list?
  def notify_on?(event)
    Array(notification_events).include?(event) && notification_email_list.any?
  end

  def notify_subscribers_later(entry, event, payload)
    Collection::NotifySubscribersJob.perform_later(id, entry.id, event, payload) if notify_on?(event)
  end

  # Entries are passed by id, not as records: a deleted entry's announcement
  # still has to reach its subscribers, and a discarded entry can't be loaded
  # through the default scope.
  def notify_subscribers_now(entry_id, event, payload)
    return unless notify_on?(event)

    entry = CollectionEntry.with_discarded.find_by(id: entry_id) if defined?(CollectionEntry.with_discarded)
    entry ||= CollectionEntry.find_by(id: entry_id)

    CollectionEventMailer
      .with(collection: self, entry: entry, event: event, payload: payload, recipients: notification_email_list)
      .event
      .deliver_now
  end

  private

  def validate_notification_events
    return errors.add(:notification_events, "must be an array") unless notification_events.is_a?(Array)

    bad = Array(notification_events) - NOTIFICATION_EVENTS
    errors.add(:notification_events, "unknown: #{bad.join(", ")}") if bad.any?
  end
end
