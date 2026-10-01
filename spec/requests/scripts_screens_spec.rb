# frozen_string_literal: true

require "rails_helper"

# Tools › Scripts: the list, the New script sheet (custom or from a preset,
# loaded into its frame), and the edit page's two-thirds layout.
RSpec.describe "Scripts screens", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "adds a script from the sheet, and reopens it when the add is refused" do
    get scripts_path
    expect(response.body).to include("dialog--sheet", 'turbo-frame id="new_script"', "Custom script", "Google Analytics 4")

    get new_script_path(preset: "ga4"), headers: {"Turbo-Frame" => "new_script"}
    expect(response.body).to include("Measurement ID", 'name="preset"')

    post scripts_path, params: {preset: "ga4", preset_id: "", script: {name: "GA", category: "analytics", placement: "head", active: "1"}}
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('data-dialog-auto-open-value="true"', "Measurement ID")

    post scripts_path, params: {preset: "ga4", preset_id: "G-ABC123", script: {name: "GA", category: "analytics", placement: "head", active: "1"}}
    expect(response).to redirect_to(scripts_path)
    expect(Script.find_by!(name: "GA").src).to include("G-ABC123")
  end

  it "opens the sheet at /scripts/new" do
    get new_script_path
    expect(response.body).to include('data-dialog-auto-open-value="true"', "Script URL")
  end

  it "edits a script beside its Save box" do
    script = Script.create!(name: "Pixel", category: "marketing", code: "fbq()")

    get edit_script_path(script)
    expect(response.body).to include("content-form--thirds", "Save changes", "script_delete_form")

    patch script_path(script), params: {script: {name: "Meta pixel", active: "0"}}
    expect(script.reload).to have_attributes(name: "Meta pixel", active: false)
  end
end
