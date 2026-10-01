# frozen_string_literal: true

require "rails_helper"

# Jbuilder views encode the way `render json:` did (config/initializers/
# jbuilder.rb): "&", "<" and ">" as themselves, not & and friends, so
# moving an endpoint to a view doesn't change a byte of its response.
RSpec.describe "API JSON encoding", type: :request do
  it "leaves HTML characters unescaped in a jbuilder response" do
    admin = create(:user)
    Page.create!(slug: "qa", title: "Q&A <b>", status: "draft", locale: "en")

    get "/api/pages/qa", headers: {"Authorization" => "Bearer #{admin.api_token.token}"}

    expect(response.body).to include(%("title":"Q&A <b>"))
  end
end
