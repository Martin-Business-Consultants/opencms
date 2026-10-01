# frozen_string_literal: true

# Where `cms login` (and the Astro installer, for a site's own token) sends
# someone to approve a terminal.
#
# The person is already signed in here, which is the whole security story: the
# browser proves who they are, and approving links their account to the machine
# holding the matching device code. Typing the code is the second factor — the
# machine cannot approve itself.
class DeviceApprovalsController < ApplicationController
  skip_authorization

  def new
    @authorization = DeviceAuthorization.find_by_user_code(params[:code]) if params[:code].present?
    @code = params[:code]
  end

  def create
    authorization = DeviceAuthorization.find_by_user_code(params[:code])

    if authorization.nil? || authorization.expired?
      return redirect_to(connect_path, alert: "That code has expired or doesn't exist. Run `cms login` again.")
    end

    if params[:decision] == "deny"
      authorization.deny!
      redirect_to connect_path, notice: "Denied. Nothing was connected."
    elsif !authorization.approvable_by?(Current.user)
      redirect_to connect_path, alert: "Connecting a site issues a service token, which your role can't do. Ask someone who manages settings."
    else
      authorization.approve!(Current.user)
      notice = if authorization.site?
        "Connected — #{authorization.label.presence || "the site"} has a read-only token of its own."
      else
        "Connected — #{authorization.hostname.presence || "that machine"} can now act as you."
      end
      redirect_to connect_path, notice: notice
    end
  end
end
