# frozen_string_literal: true

# Runs one queued Report (Report::Runnable#run_now).
class Report::RunJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  # `**` swallows the `tenant:` that jobs queued before this app became a
  # single install still carry. Drop it once those have drained.
  def perform(report_id, **)
    Report.find_by(id: report_id)&.run_now
  end
end
