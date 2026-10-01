# frozen_string_literal: true

module Hello
  # A plugin's settings page: it renders in the core settings layout and is
  # listed under Settings › Plugins.
  class SettingsController < ::Settings::BaseController
    include PluginGated
    plugin :hello

    requires_capability "settings:read", only: :show
    requires_capability "settings:write", only: :update

    def show
      @settings = Setting.get("hello")
    end

    def update
      Setting.set("hello", {"default_message" => params.require(:settings).permit(:default_message)[:default_message].to_s.strip})
      Event.record("settings.hello_updated")
      redirect_to hello_settings_path, notice: "Hello settings saved"
    end
  end
end
