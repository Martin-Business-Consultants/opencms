# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Recommendations", type: :request do
  def auth_headers(capabilities)
    actor = create(:user, admin: false, role: create(:role, permissions: capabilities))
    {"Authorization" => "Bearer #{actor.api_token.token}"}
  end

  let(:writer) { auth_headers(["recommendations:read", "recommendations:write"]) }

  def json = JSON.parse(response.body)

  describe "POST /api/recommendations" do
    it "403s for a token that can only read" do
      post "/api/recommendations",
        params: {recommendation: {kind: "content_gap", title: "x"}},
        headers: auth_headers(["recommendations:read"])

      expect(response).to have_http_status(:forbidden)
    end

    it "files an advisory finding with no subject" do
      post "/api/recommendations", params: {
        recommendation: {
          kind: "content_gap", title: "No page for “pricing for teams”",
          body: "Nothing covers it.", impact: 4,
          evidence: {searched: "pricing"}
        }
      }, headers: writer

      expect(response).to have_http_status(:created)
      expect(json.dig("recommendation", "kind")).to eq("content_gap")
      expect(json.dig("recommendation", "actionable")).to be(false)
      expect(Recommendation.open.count).to eq(1)
    end

    # Agents work in paths, not database ids — they have just read the page.
    it "resolves a subject by path" do
      page = Page.create!(title: "Pricing", slug: "pricing", status: "published", locale: "en")

      post "/api/recommendations", params: {
        recommendation: {kind: "metadata", title: "Title is too long", proposed_changes: {title: "Pricing"}},
        subject: {type: "Page", path: page.path}
      }, headers: writer

      expect(response).to have_http_status(:created)
      expect(Recommendation.last.subject).to eq(page)
      expect(json.dig("recommendation", "actionable")).to be(true)
    end

    # A content gap is by definition about a page that doesn't exist, so an
    # unresolvable subject must not be an error.
    it "files the finding anyway when the subject can't be resolved" do
      post "/api/recommendations", params: {
        recommendation: {kind: "content_gap", title: "Missing page"},
        subject: {type: "Page", path: "does/not/exist"}
      }, headers: writer

      expect(response).to have_http_status(:created)
      expect(Recommendation.last.subject).to be_nil
    end

    it "rejects an unknown kind" do
      post "/api/recommendations",
        params: {recommendation: {kind: "vibes", title: "x"}}, headers: writer

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "resolving" do
    # Separation of duties: a worker files findings, a human decides them.
    # There is deliberately no API route to resolve one.
    it "is not reachable from the API at all" do
      post "/api/recommendations/1/accept", headers: writer

      expect(response).to have_http_status(:not_found)
    end
  end
end
