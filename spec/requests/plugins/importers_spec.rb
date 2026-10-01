# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# The Importers plugin (engines/importers): Tools › Import and
# /api/tools/import, one adapter per source.
RSpec.describe "Importers plugin", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user) }
  let(:headers) { {"Authorization" => "Bearer #{admin.api_token.token}"} }

  around do |example|
    Dir.mktmpdir do |dir|
      Importers.staging_root = dir
      example.run
    ensure
      Importers.staging_root = nil
    end
  end

  def xml = Rack::Test::UploadedFile.new(StringIO.new("<rss/>"), "text/xml", original_filename: "wp.xml")

  context "while off" do
    it "has no pages, API or menu link" do
      sign_in_as admin

      get tools_import_path
      expect(response).to have_http_status(:not_found)
      get "/api/tools/import", headers: headers
      expect(response).to have_http_status(:not_found)
      post "/api/tools/import/wordpress", params: {file: xml}, headers: headers
      expect(response).to have_http_status(:not_found)

      get tools_backup_path
      expect(response.body).not_to include(">Import<")
    end
  end

  context "while on" do
    before do
      switch_plugin :importers, on: true
      sign_in_as admin
    end

    it "offers a tab per source, first in the Tools menu" do
      get tools_import_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WordPress", "Directus", "Astro", "WXR file", "Start over")
      tools = submenu_labels("Tools")
      expect(tools.index("Import")).to be < tools.index("Redirects")

      get tools_import_path(tab: "astro")
      expect(response.body).to include("GitHub repository URL")
    end

    it "queues an import from the page, or says what's missing" do
      post tools_import_run_path("wordpress")
      expect(flash[:alert]).to eq("Pick a WordPress XML (WXR) export file.")

      post tools_import_run_path("wordpress"), params: {file: xml}
      expect(response).to redirect_to(tools_import_path(tab: "wordpress"))
      expect(flash[:notice]).to match(/WordPress import queued/)
      expect(Importers::WordpressJob).to have_been_enqueued
      expect(AuditLog.last).to have_attributes(action: "import.queued")

      post tools_import_run_path("astro"), params: {repo: "https://gitlab.com/x/y"}
      expect(flash[:alert]).to eq("That doesn't look like a github.com URL.")
    end

    it "says so when the Directus file isn't SQLite" do
      post tools_import_run_path("directus"), params: {file: Rack::Test::UploadedFile.new(StringIO.new("nope"), "application/octet-stream", original_filename: "x.db")}

      expect(flash[:alert]).to match(/doesn't look like a valid Directus SQLite export/)
    end

    it "wipes imported content once the site key is typed" do
      Page.create!(slug: "about", title: "About", status: "draft", locale: "en")

      delete tools_import_wipe_path, params: {confirm: "nope"}
      expect(flash[:alert]).to match(/didn't match/)
      expect(Page.count).to eq(1)

      delete tools_import_wipe_path, params: {confirm: Site.key, tab: "directus"}
      expect(response).to redirect_to(tools_import_path(tab: "directus"))
      expect(flash[:notice]).to include("Wiped 1 pages")
      expect(Page.count).to eq(0)
    end

    it "runs over the API and lists itself in the manifest" do
      get "/api/tools/import", headers: headers
      expect(response.parsed_body["sources"]).to eq(%w[wordpress old_mill directus astro])

      post "/api/tools/import/astro", params: {repo: "https://github.com/acme/site"}, headers: headers, as: :json
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to include("source" => "astro", "repo" => "https://github.com/acme/site")

      post "/api/tools/import/nope", params: {}, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      get "/api/manifest", headers: headers
      expect(response.parsed_body["plugins"].map { it["key"] }).to include("importers")
    end

    context "with an adapter another plugin adds" do
      let(:ghost) do
        Class.new(Importers::Adapter) do
          def self.key = "ghost"
          def self.label = "Ghost"
          def self.description = "A Ghost JSON export."

          def queue
            raise Importers::Adapter::Invalid.new("Pick a Ghost export.", api_message: "file is required") if params[:file].blank?

            Importers::Adapter::Queued.new(notice: "Ghost import queued.", api_message: "Import queued.", api: {posts: 3})
          end
        end
      end

      before do
        Cms::Plugins.register :ghost_importer, name: "Ghost importer", version: "0.1.0", description: "Ghost.", enabled_by_default: true
        Cms::Plugins.importer :ghost_importer, "ghost", ghost
      end

      after { forget_plugin(:ghost_importer) }

      it "gets a tab and an API source" do
        get tools_import_path(tab: "ghost")
        expect(response.body).to include("A Ghost JSON export.")

        post "/api/tools/import/ghost", params: {file: "x"}, headers: headers, as: :json
        expect(response.parsed_body).to eq("ok" => true, "queued" => true, "source" => "ghost", "posts" => 3, "message" => "Import queued.")

        post "/api/tools/import/ghost", params: {}, headers: headers, as: :json
        expect(response.parsed_body).to eq("error" => "invalid", "message" => "file is required")
      end
    end
  end
end
