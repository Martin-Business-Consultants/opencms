# frozen_string_literal: true

# Settings → Appearance: light, dark or follow the system. Stored in the
# browser (localStorage "appearance"), so there's nothing to save here and
# nothing to gate.
class Settings::AppearancesController < Settings::BaseController
  skip_authorization

  def show
  end
end
