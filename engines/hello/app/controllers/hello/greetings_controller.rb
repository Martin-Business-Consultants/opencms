# frozen_string_literal: true

module Hello
  class GreetingsController < ::ApplicationController
    include PluginGated
    plugin :hello

    requires_capability "hello:read", only: :index
    requires_capability "hello:write", only: :create

    def index
      @greetings = paginate(Greeting.newest_first)
      @greeting = Greeting.new(message: Greeting.default_message)
    end

    def create
      @greeting = Greeting.new(message: params.require(:greeting).permit(:message)[:message], user: Current.user)

      if @greeting.save
        redirect_to hello_greetings_path, notice: "Said hello"
      else
        @greetings = paginate(Greeting.newest_first)
        render :index, status: :unprocessable_content
      end
    end
  end
end
