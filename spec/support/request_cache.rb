# frozen_string_literal: true

# Wipe rate-limit counters (and any other transient cache state) between
# request specs so the order of test execution can't leak throttle counts
# from one spec into another.
RSpec.configure do |config|
  config.before(:each, type: :request) { Rails.cache.clear }
end
