# frozen_string_literal: true

require "rails_helper"

# The dashboard's getting-started checklist. The site audit line under it is
# covered in site_audit_spec.
RSpec.describe "Dashboard", type: :request do
  before do
    sign_in_as create(:user)
    Setting.delete_key(OnboardingChecklist::SETTING_KEY)
  end

  it "shows the checklist in the Hotwire layout" do
    get dashboard_url

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Get started", "Connect your Astro site", "<progress")
  end

  it "ticks off and unticks a step done on someone's machine" do
    post dashboard_checklist_acknowledgements_url, params: {key: "scaffold_site"}
    expect(response).to redirect_to(dashboard_url)
    expect(OnboardingChecklist.manually_acknowledged?("scaffold_site")).to be(true)

    delete dashboard_checklist_acknowledgement_url("scaffold_site")
    expect(OnboardingChecklist.manually_acknowledged?("scaffold_site")).to be(false)
  end

  it "hides the checklist once dismissed" do
    post dashboard_checklist_dismissal_url
    get dashboard_url

    expect(response.body).not_to include("Get started")
  end
end
