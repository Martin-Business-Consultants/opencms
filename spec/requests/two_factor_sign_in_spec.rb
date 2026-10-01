# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Two-factor sign-in", type: :request do
  let(:user) { create(:user) }

  before do
    user.setup_totp_secret!
    code = TwoFactor.code_at(user.totp_secret, Time.current.to_i / TwoFactor::STEP_SECONDS)
    user.enable_totp!(code)
  end

  it "redirects to the challenge page after the password step" do
    post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}
    expect(response).to redirect_to(sessions_challenge_url)
  end

  it "completes sign-in with a valid TOTP code" do
    post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}

    code = TwoFactor.code_at(user.totp_secret, Time.current.to_i / TwoFactor::STEP_SECONDS)
    post sessions_challenge_url, params: {code: code}
    expect(response).to redirect_to(pages_url)

    get pages_url
    expect(response).to have_http_status(:success)
  end

  it "rejects a wrong code" do
    post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}
    post sessions_challenge_url, params: {code: "000000"}
    expect(response).to redirect_to(sessions_challenge_url)
  end

  it "accepts a recovery code (single-use)" do
    user.reload
    code = TwoFactor.code_at(user.totp_secret, Time.current.to_i / TwoFactor::STEP_SECONDS)
    user.enable_totp!(code)
    plaintexts = user.regenerate_recovery_codes!

    post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}
    post sessions_challenge_url, params: {code: plaintexts.first}
    expect(response).to redirect_to(pages_url)
  end
end
