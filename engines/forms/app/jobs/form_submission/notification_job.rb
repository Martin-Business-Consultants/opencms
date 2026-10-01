# frozen_string_literal: true

require "net/http"

class FormSubmission::NotificationJob < ApplicationJob
  queue_as :default

  retry_on Net::HTTPError, wait: 30.seconds, attempts: 2
  retry_on Errno::ECONNREFUSED, wait: 30.seconds, attempts: 2

  # `_tenant`: jobs queued before single installs carry a trailing tenant.
  def perform(submission_id, _tenant = nil)
    FormSubmission.find_by(id: submission_id)&.notify_now
  end
end
