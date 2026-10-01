# frozen_string_literal: true

# A new secret in place of the old one, which stops working at once. The
# page re-renders and the new plaintext is revealed like any other time.
class Settings::ApiTokens::RotationsController < Settings::BaseController
  skip_authorization

  def create
    token = ApiToken.for(Current.user)
    token.rotate!

    redirect_to settings_api_token_path,
      notice: "Token rotated. The previous one stopped working immediately — update anything that was using it."
  end
end
