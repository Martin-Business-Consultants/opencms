# frozen_string_literal: true

# Emails a collection's subscribers about one entry event
# (Collection#notify_subscribers_now).
class Collection::NotifySubscribersJob < ApplicationJob
  queue_as :default

  def perform(collection_id, entry_id, event, payload)
    Collection.find_by(id: collection_id)&.notify_subscribers_now(entry_id, event, payload)
  end
end
