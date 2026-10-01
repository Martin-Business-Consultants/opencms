# frozen_string_literal: true

# Daily: is there a newer CMS release (UpdateCheck)? And settle any update
# that finished or went quiet while nobody had Settings › Updates open.
class UpdateCheckJob < ApplicationJob
  queue_as :default

  def perform
    UpdateCheck.check_now if UpdateCheck.checking?
  ensure
    Upgrade.settle_running
  end
end
