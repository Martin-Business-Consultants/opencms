# frozen_string_literal: true

# Sets environment variables for the block and puts back what was there,
# for the settings an install reads from its environment (CMS_UPDATES, …).
# A nil value unsets one.
module EnvHelpers
  def with_env(vars)
    saved = vars.keys.to_h { [it, ENV[it]] }
    vars.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end
end

RSpec.configure { it.include EnvHelpers }
