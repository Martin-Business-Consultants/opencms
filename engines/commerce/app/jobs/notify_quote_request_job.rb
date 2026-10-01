# frozen_string_literal: true

# Renamed to QuoteRequest::NotificationJob. Kept one release so jobs queued
# under the old name still run; remove after.
class NotifyQuoteRequestJob < QuoteRequest::NotificationJob
end
