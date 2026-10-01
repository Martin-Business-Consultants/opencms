# frozen_string_literal: true

# Switching two-factor on: the code proves the authenticator has the secret.
# Renders the Two-factor page with the new recovery codes — shown this once.
class Settings::TwoFactors::ActivationsController < Settings::BaseController
  skip_authorization

  def create
    user = Current.user
    success, @recovery_codes = user.enable_totp!(params[:code].to_s)

    if success
      Event.record("two_factor.enabled", target: user)
      render "settings/two_factors/show"
    else
      @code_error = "That code is not valid. Check the time on your device and try again."
      render "settings/two_factors/show", status: :unprocessable_content
    end
  end
end
