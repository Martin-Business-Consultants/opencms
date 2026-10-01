# frozen_string_literal: true

# For a plugin's controllers: its pages and API are 404 while it's switched
# off, before authentication or authorization get a say.
#
#   class Hello::GreetingsController < ApplicationController
#     include PluginGated
#     plugin :hello
#   end
module PluginGated
  extend ActiveSupport::Concern

  class_methods do
    def plugin(key)
      prepend_before_action { head :not_found unless Cms::Plugins.enabled?(key) }
    end
  end
end
