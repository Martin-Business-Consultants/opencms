# frozen_string_literal: true

require "hello/engine"

# The reference plugin: a list of greetings. It exists to show every
# extension point in one small place (docs/plugins.md walks through it).
module Hello
  # Plugin tables are prefixed with the plugin's key.
  def self.table_name_prefix = "hello_"
end
