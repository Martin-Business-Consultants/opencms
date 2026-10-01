# frozen_string_literal: true

class Settings::SessionsController < Settings::BaseController
  skip_authorization

  def index
    @sessions = Current.user.sessions.order(created_at: :desc)
  end
end
