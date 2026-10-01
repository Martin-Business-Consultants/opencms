# frozen_string_literal: true

require "rails_helper"

# The findings console.
#
# Two behaviours carry the whole design, so they are pinned here: the review
# sits beside the queue rather than on a page of its own, and deciding one
# finding opens the next.
RSpec.describe "Recommendations", type: :request do
  def sign_in_with(capabilities)
    user = create(:user, admin: false, role: create(:role, permissions: capabilities))
    sign_in_as(user)
    user
  end

  let!(:first) do
    Recommendation.create!(kind: "metadata", title: "Title is too long", impact: 5)
  end

  let!(:second) do
    Recommendation.create!(kind: "schema", title: "No FAQ schema", impact: 3)
  end

  describe "GET /recommendations" do
    it "renders the queue with no review open" do
      sign_in_with(["recommendations:read"])

      get "/recommendations"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Title is too long", "No FAQ schema")
      expect(response.body).to include(ERB::Util.html_escape(Recommendation::QueueState.new(open: Recommendation.open.to_a).headline))
      expect(response.body).not_to include('id="review"')
    end
  end

  # A direct visit to a finding answers with the whole queue behind it — that
  # is what makes the URL shareable and Back-able.
  describe "GET /recommendations/:id" do
    it "renders the queue with the review beside it, naming the next finding" do
      sign_in_with(["recommendations:read", "recommendations:resolve"])

      get "/recommendations/#{first.id}"

      expect(response.body).to include('id="review"', "No FAQ schema")
      expect(response.body).to match(/name="next_id"[^>]*value="#{second.id}"/)
    end
  end

  describe "deciding" do
    before { sign_in_with(["recommendations:read", "recommendations:resolve"]) }

    it "opens the next finding the client named" do
      post "/recommendations/#{first.id}/acceptance", params: {next_id: second.id}

      expect(first.reload).to be_accepted
      expect(response).to redirect_to("/recommendations/#{second.id}")
    end

    # A stale id means someone else decided it while this page was open. The
    # decision still succeeded, so falling back to the queue is right and
    # 404ing would be a lie about what happened.
    it "falls back to the queue when the next one is already gone" do
      second.dismiss!(by: Current.user)

      post "/recommendations/#{first.id}/acceptance", params: {next_id: second.id}

      expect(first.reload).to be_accepted
      expect(response).to redirect_to("/recommendations")
    end

    it "returns to the queue when the client names no next one" do
      post "/recommendations/#{first.id}/dismissal"

      expect(response).to redirect_to("/recommendations")
    end

    it "refuses someone who can only read" do
      sign_in_with(["recommendations:read"])

      post "/recommendations/#{first.id}/acceptance"

      expect(first.reload).to be_open
    end
  end
end
