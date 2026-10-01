# frozen_string_literal: true

# Every Settings page renders in the settings layout: its title across the
# top, the page in two thirds, and a sidebar in the other third (its Save box,
# when it has one, and the Settings sections).
class Settings::BaseController < ApplicationController
  layout "settings"

  private

  def settings_screen? = true
end
