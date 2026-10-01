# frozen_string_literal: true

module Hello
  module Api
    # GET /api/hello/greetings — listed with the plugin in /api/manifest.
    class GreetingsController < ::Api::BaseController
      include PluginGated
      plugin :hello

      def index
        require_capability!("hello:read")

        @greetings = Greeting.newest_first.limit(50)
      end
    end
  end
end
