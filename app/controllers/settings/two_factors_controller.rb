# frozen_string_literal: true

# Settings → Two-factor: TOTP enrolment and disabling.
#
#   GET    /settings/two_factor                 — current state; mints a secret
#                                                 for someone starting fresh
#   POST   /settings/two_factor/activation      — verify a code and switch it on
#                                                 (Settings::TwoFactors::ActivationsController)
#   POST   /settings/two_factor/recovery_codes  — fresh codes
#                                                 (Settings::TwoFactors::RecoveryCodesController)
#   DELETE /settings/two_factor                 — switch it off
#
# Recovery codes are shown once, on the page the activation or regeneration
# renders, and never stored in plaintext.
class Settings::TwoFactorsController < Settings::BaseController
  skip_authorization

  def show
    user = Current.user
    user.setup_totp_secret! if user.totp_secret.blank? && !user.totp_enabled?
  end

  def destroy
    Current.user.disable_totp!
    Event.record("two_factor.disabled", target: Current.user)
    redirect_to settings_two_factor_path, notice: "Two-factor authentication disabled"
  end
end
