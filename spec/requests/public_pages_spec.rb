# frozen_string_literal: true

require "rails_helper"

# The signed-out pages: they render in layouts/public (no admin nav) and
# re-render with their errors rather
# than redirecting them away. The flows behind them are covered in
# sessions_spec, two_factor_sign_in_spec, users_spec and identity/*.
RSpec.describe "Public pages", type: :request do
  let(:user) { create(:user) }

  def expect_public_page(*texts)
    expect(response.body).to include(*texts)
    expect(response.body).to include('class="public"')
  end

  it "renders sign in" do
    get sign_in_url

    expect(response).to have_http_status(:success)
    expect_public_page("Log in to your account", "Forgot password?")
  end

  it "renders the two-factor challenge only mid sign-in" do
    get sessions_challenge_url
    expect(response).to redirect_to(sign_in_url)

    user.setup_totp_secret!
    user.enable_totp!(TwoFactor.code_at(user.totp_secret, Time.current.to_i / TwoFactor::STEP_SECONDS))
    post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}
    get sessions_challenge_url

    expect(response).to have_http_status(:success)
    expect_public_page("Two-factor verification", "one-time-code")
  end

  it "re-renders sign up with the reasons it failed" do
    post sign_up_url, params: {name: "Ann", email: "not-an-email", password: "short", password_confirmation: "short"}

    expect(response).to have_http_status(:unprocessable_content)
    expect_public_page("That didn’t work", "Email is invalid", 'value="Ann"')
  end

  it "re-renders the password reset form when the passwords don't match" do
    sid = user.generate_token_for(:password_reset)

    get edit_identity_password_reset_url(sid:)
    expect_public_page("Reset password", user.email)

    patch identity_password_reset_url, params: {sid:, password: "Secret6*4*2*", password_confirmation: "Different1*2"}
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Password confirmation doesn&#39;t match")
  end

  it "sends the root path to sign in, or to the pages list once signed in" do
    get root_url
    expect(response).to redirect_to(sign_in_url)

    sign_in_as create(:user)
    get root_url
    expect(response).to redirect_to(pages_url)
  end
end
