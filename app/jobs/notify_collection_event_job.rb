# frozen_string_literal: true

# The job's old name, kept so notifications queued before
# Collection::NotifySubscribersJob replaced it still send. Remove once those
# have drained (one release). `_tenant` is only for jobs queued before this app
# became a single install.
class NotifyCollectionEventJob < Collection::NotifySubscribersJob
  def perform(collection_id, entry_id, event, payload, _tenant = nil)
    super(collection_id, entry_id, event, payload)
  end
end
