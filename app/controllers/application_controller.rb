# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :use_site_time_zone, if: :admin_page_request?
  before_action :set_current_request_details
  before_action :authenticate

  # Authorization runs after authentication so Current.user / Current.api_user
  # are available; declared here last so the before_action order is correct.
  include Authorization

  helper_method :search_term, :settings_screen?

  private

  # Every time the admin shows or reads (schedules, cards, timestamps) is in
  # the site's zone (Settings › General); what's stored stays UTC. Pages only:
  # JSON keeps rendering times in UTC, as the API always has.
  def use_site_time_zone(&)
    Time.use_zone(Site.time_zone, &)
  end

  def admin_page_request?
    request.format.html? || request.format.turbo_stream?
  end

  # A list's search term (WordPress's ?s=), or nil.
  # Whether this is a Settings page (Settings::BaseController), which lays its
  # title out above the page and a sidebar (layouts/settings).
  def settings_screen? = false

  def search_term
    params[:s].to_s.strip.presence
  end

  # One page of an index list, Fizzy's way (geared_pagination: 15, then 30, 50,
  # 100 a page), with @page for the view's "load more".
  def paginate(records)
    set_page_and_extract_portion_from records
  end

  def authenticate
    redirect_to sign_in_path unless perform_authentication
  end

  def require_no_authentication
    return unless perform_authentication

    flash[:notice] = "You are already signed in"
    redirect_to root_path
  end

  def perform_authentication
    Current.session ||= Session.find_by_id(cookies.signed[:session_token])
  end

  def set_current_request_details
    Current.user_agent = request.user_agent
    Current.ip_address = request.ip
    Current.remote_ip = request.remote_ip
  end
end
