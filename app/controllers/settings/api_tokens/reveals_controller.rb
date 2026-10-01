# frozen_string_literal: true

# POST /settings/api_token/reveal — the plaintext, into the page's secret
# frame (or as {token:} for JSON). 410 for a token minted before plaintext
# was stored: it authenticates fine, there's simply nothing to show until
# it's rotated.
class Settings::ApiTokens::RevealsController < Settings::BaseController
  skip_authorization

  def create
    @token = ApiToken.for(Current.user)

    if @token.visible?
      @token.reveal
      respond_to do |format|
        format.html { render layout: false }
        format.json { render json: {token: @token.token} }
      end
    else
      respond_to do |format|
        format.html { render layout: false, status: :gone }
        format.json { render json: {error: "rotation_required"}, status: :gone }
      end
    end
  end
end
