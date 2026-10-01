# frozen_string_literal: true

require "rails_helper"

# The envelope is opt-in per request. That is the whole design: a browser, a
# webhook consumer and the old shell CLI all keep the exact shape they get
# today, and an agent that asks for it gets an answer that says what it is and
# what to do next.
RSpec.describe "Api agent envelope", type: :request do
  def auth_headers(capabilities = ["pages:read", "pages:write", "pages:publish"], extra = {})
    actor = create(:user, admin: false, role: create(:role, permissions: capabilities))
    {"Authorization" => "Bearer #{actor.api_token.token}"}.merge(extra)
  end

  def json = JSON.parse(response.body)

  describe "without asking for it" do
    it "returns the payload exactly as it always did" do
      get "/api/pages", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(json).to have_key("pages")
      expect(json).not_to have_key("status")
      expect(json).not_to have_key("breadcrumbs")
    end
  end

  describe "asking for it" do
    it "wraps the payload when the header is set" do
      get "/api/pages", headers: auth_headers.merge("X-Agent-Envelope" => "1")

      expect(json.keys).to include("status", "summary", "data", "breadcrumbs")
      expect(json["status"]).to eq("ok")
      expect(json.dig("data", "pages")).to be_an(Array)
    end

    it "wraps the payload when ?envelope=1 is set" do
      get "/api/pages?envelope=1", headers: auth_headers

      expect(json.keys).to include("status", "summary", "data")
    end

    # A summary that counts the collection is the difference between an answer
    # an agent has to measure and one it can read.
    it "summarises what came back" do
      Page.create!(title: "About", slug: "about", status: "published", locale: "en")

      get "/api/pages", headers: auth_headers.merge("X-Agent-Envelope" => "1")

      expect(json["summary"]).to match(/\d+ page/i)
    end

    # Breadcrumbs are the point of the envelope: every answer carries the next
    # call, so an agent never has to guess the path or re-read a usage screen.
    it "carries runnable next steps, not prose" do
      Page.create!(title: "About", slug: "about", status: "published", locale: "en")

      get "/api/pages", headers: auth_headers.merge("X-Agent-Envelope" => "1")

      crumbs = json.fetch("breadcrumbs")
      expect(crumbs).to be_present
      crumbs.each do |crumb|
        expect(crumb).to include("description", "command")
        expect(crumb["command"]).to be_present
      end
    end

    it "names the specific record it just returned" do
      Page.create!(title: "Pricing", slug: "pricing", status: "published", locale: "en")

      get "/api/pages/pricing", headers: auth_headers.merge("X-Agent-Envelope" => "1")

      expect(json["breadcrumbs"].map { |c| c["command"] }.join(" ")).to include("pricing")
    end
  end

  # An error an agent can act on says which of the two it is: a 403 means ask a
  # human to widen the role, and a 422 means fix the payload. Both are failures
  # of the request, and only one of them is worth retrying.
  describe "when the request fails" do
    it "reports a refused capability as an error status, not an ok envelope" do
      get "/api/pages", headers: auth_headers([]).merge("X-Agent-Envelope" => "1")

      expect(response).to have_http_status(:forbidden)
      expect(json["status"]).to eq("error") if json.key?("status")
    end
  end
  # The envelope is decoration on a response that already succeeded. A summary
  # or breadcrumb block that raises must cost the caller a nice sentence, not
  # the payload — this exact bug turned a working `cms work` into a 500.
  describe "when a declaration itself is broken" do
    around do |example|
      controller = Api::PagesController
      summaries = controller._agent_summaries
      crumbs = controller._agent_breadcrumbs
      controller._agent_summaries = summaries.merge(index: ->(_payload) { raise "boom" })
      controller._agent_breadcrumbs = crumbs.merge(index: ->(_payload) { raise "boom" })
      example.run
      controller._agent_summaries = summaries
      controller._agent_breadcrumbs = crumbs
    end

    it "still returns the payload, with a fallback summary and no breadcrumbs" do
      Page.create!(title: "About", slug: "about", status: "published", locale: "en")

      get "/api/pages", headers: auth_headers.merge("X-Agent-Envelope" => "1")

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "pages").size).to eq(1)
      expect(json["summary"]).to be_present
      expect(json["breadcrumbs"]).to eq([])
    end
  end
end
