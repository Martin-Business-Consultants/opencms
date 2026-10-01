# frozen_string_literal: true

# Renamed to FormSubmission::NotificationJob. Kept one release so jobs queued
# under the old name still run; remove after.
class NotifyFormSubmissionJob < FormSubmission::NotificationJob
end
