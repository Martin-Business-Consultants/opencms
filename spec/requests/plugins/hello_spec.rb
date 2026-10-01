# frozen_string_literal: true

require "rails_helper"

# The reference plugin (engines/hello) through every extension point it uses.
RSpec.describe "The Hello plugin", type: :request do
  let(:admin) { create(:user) }

  def api_headers(user = admin) = {"Authorization" => "Bearer #{user.api_token.token}"}

  context "while off" do
    it "is 404, pages and API alike, and adds nothing to the admin" do
      sign_in_as admin

      get hello_greetings_path
      expect(response).to have_http_status(:not_found)

      get "/api/hello/greetings", headers: api_headers
      expect(response).to have_http_status(:not_found)

      get dashboard_path
      expect(response.body).not_to include("hello/hello", "All greetings", "Greetings</a>")

      get "/api/manifest", headers: api_headers
      expect(JSON.parse(response.body)["plugins"].map { it["key"] }).not_to include("hello")
    end
  end

  context "while on" do
    before { switch_plugin :hello, on: true }

    it "adds its menu link, stylesheet and dashboard panel" do
      sign_in_as admin

      get dashboard_path

      expect(response.body).to include(hello_greetings_path, "hello/hello", "Nobody has said hello yet.")
    end

    it "keeps greetings in its own table" do
      sign_in_as admin

      post hello_greetings_path, params: {greeting: {message: "Hi there"}}

      expect(response).to redirect_to(hello_greetings_path)
      expect(Hello::Greeting.last).to have_attributes(message: "Hi there", user: admin)
      expect(Hello::Greeting.table_name).to eq("hello_greetings")

      get hello_greetings_path
      expect(response.body).to include("Hi there")
    end

    it "re-renders a blank greeting with its error" do
      sign_in_as admin

      post hello_greetings_path, params: {greeting: {message: ""}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That didn’t work")
    end

    it "gates on its own capabilities" do
      sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))

      get hello_greetings_path

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/permission/)
    end

    it "has a settings page in the settings layout" do
      sign_in_as admin

      patch hello_settings_path, params: {settings: {default_message: "Howdy"}}
      get hello_settings_path

      expect(response.body).to include("Howdy", "settings-screen")
      expect(Hello::Greeting.default_message).to eq("Howdy")
    end

    it "serves its API and lists it in the manifest" do
      Hello::Greeting.create!(message: "From the API")

      get "/api/hello/greetings", headers: api_headers
      expect(JSON.parse(response.body)["greetings"].first["message"]).to eq("From the API")

      get "/api/manifest", headers: api_headers
      expect(JSON.parse(response.body)["plugins"]).to include(
        {"key" => "hello", "name" => "Hello", "version" => "0.1.0",
         "endpoints" => [{"path" => "/api/hello/greetings", "description" => "The greetings, newest first."}]}
      )
    end

    it "offers its capabilities in the role editor" do
      expect(Permissions.catalog["Hello"]).to eq(%w[hello:read hello:write])
    end

    it "runs its nightly task" do
      (Hello::Greeting::KEEP + 3).times { Hello::Greeting.create!(message: "hi") }

      PluginsNightlyJob.perform_now

      expect(Hello::Greeting.count).to eq(Hello::Greeting::KEEP)
    end

    it "hears the core's page.published event" do
      page = Page.create!(title: "About", slug: "about", status: "draft", locale: "en")

      page.update!(status: "published")

      expect(Setting.get("hello")["pages_published"]).to eq(1)
    end
  end
end
