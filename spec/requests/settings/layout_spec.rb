# frozen_string_literal: true

require "rails_helper"

# Every Settings page: its title across the top, the page in two thirds, and
# a sidebar with its Save box (when it has a form) and the sections.
RSpec.describe "Settings layout", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "puts the title above the columns, and the Save box and sections in the sidebar" do
    get settings_general_path

    body = response.body
    expect(body.index('class="page-title"')).to be < body.index("content-form--thirds")
    aside = body[%r{<aside class="content-form__aside.*?</aside>}m]
    expect(aside).to include('form="settings_form"', "Save changes", "settings-sections", 'aria-current="page"')
    expect(body).to include('id="settings_form"')

    patch settings_general_path, params: {settings: {title: "Old Mill"}}
    expect(Setting.get("general")["title"]).to eq("Old Mill")
  end

  it "shows what an API token can do as cards" do
    get settings_api_token_path

    expect(response.body).to include("settings-cards", "settings-cards__card", "settings-sections")
  end
end
