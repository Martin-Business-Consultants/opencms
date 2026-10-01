# frozen_string_literal: true

# GET /settings — every section this role can open, with what it's for.
class Settings::SectionsController < Settings::BaseController
  skip_authorization

  def index
  end
end
