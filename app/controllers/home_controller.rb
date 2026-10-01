# frozen_string_literal: true

# The root path: the pages list for someone signed in, sign in for anyone else.
class HomeController < ApplicationController
  skip_authorization
  skip_before_action :authenticate

  def index
    redirect_to(perform_authentication ? pages_path : sign_in_path)
  end
end
