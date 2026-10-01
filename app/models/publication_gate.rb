# frozen_string_literal: true

# Putting a record in front of visitors is the publish capability's job.
# Someone without it may still create and edit drafts; what their write
# can't do is publish one: set its status to published, or schedule it
# (publish_at) for the scheduler to publish later. PublicationGate takes
# exactly those changes back out of a pending save and names them, so the
# admin and the API can save the rest and ask for review instead
# (ReviewRequest.request_publication), and approving the request publishes.
#
# It reads the record's own change tracking after the attributes are
# assigned, so a draft a publisher already scheduled isn't "published again"
# by a writer editing another field. A record that's already live is the
# other gate's (GatedWrites, ContentEditing): its whole write becomes a
# Revision.
module PublicationGate
  module_function

  # Reverts the publishing changes on `record` (unsaved) and returns their
  # names, [] when the write publishes nothing.
  def withhold(record)
    held = []

    if record.respond_to?(:status) && record.status_changed? && record.status.to_s == "published"
      record.status = record.new_record? ? "draft" : record.status_in_database
      held << "status"
    end

    if record.respond_to?(:publish_at) && record.publish_at_changed? && record.publish_at.present?
      record.publish_at = record.publish_at_in_database
      held << "publish_at"
    end

    held
  end
end
