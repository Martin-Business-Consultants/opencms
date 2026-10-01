# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Approvals", type: :request do
  def sign_in_with(capabilities)
    user = create(:user, admin: false, role: create(:role, permissions: capabilities))
    sign_in_as(user)
    user
  end

  let(:page_record) do
    Page.create!(title: "Pricing", slug: "pricing", status: "published", locale: "en")
  end

  describe "GET /approvals" do
    # The queue is the editors' — revisions and review requests are content
    # work. Reading agents is not the ticket in; reading pages is.
    it "renders for someone who can read pages" do
      sign_in_with(["pages:read"])

      get "/approvals"

      expect(response).to have_http_status(:success)
    end

    it "refuses someone who can't read pages, whatever else they hold" do
      sign_in_with(["agents:read"])

      get "/approvals"

      expect(response).to have_http_status(:redirect)
    end

    # Findings are the agents' output; a role that can't see agents' findings
    # gets a two-column queue, not a 403 and not an empty third column that
    # looks like "no findings".
    it "shows the findings column only to a role that may read findings" do
      Recommendation.create!(kind: "content_gap", title: "No page for teams", status: "open", impact: 3)

      sign_in_with(["pages:read"])
      get "/approvals"
      expect(response.body).not_to include("Agent findings", "No page for teams", "agents enabled", "No agents are enabled")

      Session.delete_all
      sign_in_with(["pages:read", "recommendations:read"])
      get "/approvals"
      expect(response.body).to include("Agent findings", "No page for teams")
      # What's producing work comes from the Agents plugin, when it's on.
      expect(response.body).not_to include("No agents are enabled")

      switch_plugin :ai, on: true

      switch_plugin :agents, on: true
      get "/approvals"
      expect(response.body).to include("No agents are enabled")
    end

    # The roll-up has to show all three queues, or it isn't answering the
    # question it exists to answer.
    it "gathers revisions, review requests and findings into one page" do
      author = create(:user)
      Revision.propose!(record: page_record, attributes: {title: "Plans"}, author: author)
      ReviewRequest.create!(reviewable: page_record, requested_by: author, state: "pending")
      Recommendation.create!(kind: "content_gap", title: "No page for teams", status: "open", impact: 3)

      sign_in_with(["pages:read", "pages:publish", "recommendations:read", "recommendations:resolve"])
      get "/approvals"

      expect(response.body).to include("3 items waiting", "No page for teams")
      expect(response.body.scan("Pricing").size).to be >= 2
      expect(response.body).not_to include("view only")
    end

    # The queue must not offer a button the target page will refuse.
    it "marks items undecidable for someone without the publish capability" do
      author = create(:user)
      Revision.propose!(record: page_record, attributes: {title: "Plans"}, author: author)

      sign_in_with(["pages:read"])
      get "/approvals"

      expect(response.body).to include("view only")
    end
  end

  describe "resolving a finding" do
    let!(:recommendation) do
      Recommendation.create!(kind: "metadata", title: "Title too long", status: "open")
    end

    it "records the decision without writing content" do
      sign_in_with(["recommendations:read", "recommendations:resolve"])

      post "/recommendations/#{recommendation.id}/acceptance", params: {comment: "Worth doing"}

      recommendation.reload
      expect(recommendation).to be_accepted
      expect(recommendation.decision_comment).to eq("Worth doing")
      expect(recommendation.resolved_by).to be_present
    end

    it "refuses someone who can only read findings" do
      sign_in_with(["recommendations:read"])

      post "/recommendations/#{recommendation.id}/dismissal"

      expect(recommendation.reload).to be_open
    end

    # Two reviewers deciding at once must not both win.
    it "refuses a second decision" do
      sign_in_with(["recommendations:read", "recommendations:resolve"])
      post "/recommendations/#{recommendation.id}/acceptance"

      post "/recommendations/#{recommendation.id}/dismissal"

      expect(recommendation.reload).to be_accepted
    end
  end
end
