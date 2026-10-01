# frozen_string_literal: true

class QuoteRequest::NotificationJob < ApplicationJob
  queue_as :default

  # `_tenant`: jobs queued before single installs carry a trailing tenant.
  def perform(quote_request_id, _tenant = nil)
    QuoteRequest.find_by(id: quote_request_id)&.notify_now
  end
end
