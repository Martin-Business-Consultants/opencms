# frozen_string_literal: true

# `continue` is the answer a worker acts on: false means stop now.
json.continue @extended && !@run.cancel_requested?
json.status @run.status
json.cancel_requested @run.cancel_requested?
json.lease_expires_at @run.lease_expires_at&.iso8601
json.reason @reason
