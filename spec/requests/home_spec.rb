# frozen_string_literal: true

require "rails_helper"

# Inside a workspace the root path is a signpost, not a page of its own:
# it bounces to wherever the person should start. That's Pages — the
# content is the point of the CMS, and every human role holds `pages:read`.
RSpec.describe "Home", type: :request do
  let(:user) { create(:user) }

  describe "GET / inside a workspace" do
    it "sends a signed-in user to pages" do
      post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}

      get root_url
      expect(response).to redirect_to(pages_url)
    end

    it "sends a signed-out visitor to sign in" do
      get root_url
      expect(response).to redirect_to(sign_in_url)
    end
  end
end
