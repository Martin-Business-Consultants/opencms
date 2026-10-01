# frozen_string_literal: true

require "rails_helper"

# Tools › Redirects, the first admin area on the Hotwire stack. Its API half
# is covered in spec/requests/api/parity_spec.rb.
RSpec.describe "Tools › Redirects", type: :request do
  let(:admin) { create(:user) }

  def sign_in_with(capabilities)
    sign_in_as create(:user, admin: false, role: create(:role, permissions: capabilities))
  end

  def make_redirect(source = "/old", **attrs)
    Redirect.create!({source_path: source, destination_url: "/new", status_code: 301, active: true}.merge(attrs))
  end

  describe "index" do
    it "lists every rule in the Hotwire layout" do
      sign_in_as admin
      make_redirect("/old")
      make_redirect("/off", active: false)

      get tools_redirects_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("/old", "/off", "Disabled", "turbo")
    end

    it "offers only what the role allows" do
      sign_in_with(["redirects:read"])
      make_redirect

      get tools_redirects_path

      expect(response.body).not_to include("New redirect", "Import CSV", "redirects_bulk_deletion")
    end

    it "is refused without redirects:read" do
      sign_in_with(["pages:read"])

      get tools_redirects_path

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/permission/)
    end
  end

  describe "create" do
    it "saves a rule and audits it" do
      sign_in_as admin

      expect {
        post tools_redirects_path, params: {redirect: {source_path: "old/", destination_url: "/new", status_code: 302, active: "1"}}
      }.to change(Redirect, :count).by(1)

      expect(response).to redirect_to(tools_redirects_path)
      expect(Redirect.last).to have_attributes(source_path: "/old", status_code: 302)
      expect(AuditLog.last.action).to eq("redirect.created")
    end

    it "re-renders the form with the errors" do
      sign_in_as admin

      post tools_redirects_path, params: {redirect: {source_path: "/bad*", destination_url: ""}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That didn’t work", "can&#39;t be blank")
    end
  end

  describe "update" do
    it "saves changes" do
      sign_in_as admin
      redirect = make_redirect

      patch tools_redirect_path(redirect), params: {redirect: {destination_url: "/newer", active: "0"}}

      expect(response).to redirect_to(tools_redirects_path)
      expect(redirect.reload).to have_attributes(destination_url: "/newer", active: false)
    end

    it "edits in the list's sheet, with its hits" do
      sign_in_as admin
      redirect = make_redirect(hit_count: 7)

      get edit_tools_redirect_path(redirect), headers: {"Turbo-Frame" => "redirect_sheet"}
      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="redirect_sheet"', "Last hit", "7")

      get edit_tools_redirect_path(redirect)
      expect(response.body).to include('data-dialog-auto-open-value="true"', "Edit redirect", "Last hit")

      get tools_redirects_path
      expect(response.body).to include('data-turbo-frame="redirect_sheet"', "dialog--sheet")
    end

    it "reopens the sheet when a save is refused" do
      sign_in_as admin
      redirect = make_redirect

      patch tools_redirect_path(redirect), params: {redirect: {destination_url: ""}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('data-dialog-auto-open-value="true"', "Edit redirect")
    end
  end

  describe "destroy" do
    it "deletes one rule" do
      sign_in_as admin
      redirect = make_redirect

      expect { delete tools_redirect_path(redirect) }.to change(Redirect, :count).by(-1)
      expect(AuditLog.last.action).to eq("redirect.deleted")
    end

    it "is refused without redirects:delete" do
      sign_in_with(["redirects:read", "redirects:write"])
      redirect = make_redirect

      expect { delete tools_redirect_path(redirect) }.not_to change(Redirect, :count)
    end
  end

  describe "bulk deletion" do
    it "deletes the ticked rules" do
      sign_in_as admin
      a = make_redirect("/a")
      b = make_redirect("/b")
      keep = make_redirect("/c")

      post tools_redirects_bulk_deletions_path, params: {ids: [a.id, b.id]}

      expect(response).to redirect_to(tools_redirects_path)
      expect(flash[:notice]).to eq("2 redirects deleted")
      expect(Redirect.pluck(:id)).to eq([keep.id])
    end

    it "says so when nothing was ticked" do
      sign_in_as admin

      post tools_redirects_bulk_deletions_path

      expect(flash[:alert]).to match(/Tick/)
    end
  end

  describe "CSV" do
    it "exports what import accepts" do
      sign_in_as admin
      make_redirect("/old", notes: "moved, again")

      get tools_redirects_export_path
      expect(response.media_type).to eq("text/csv")
      csv = response.body

      Redirect.delete_all
      post tools_redirects_import_path, params: {file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "r.csv")}

      expect(flash[:notice]).to eq("Import: 1 created, 0 updated")
      expect(Redirect.find_by(source_path: "/old").notes).to eq("moved, again")
    end

    it "reports rows it couldn't save" do
      sign_in_as admin
      csv = "source_path,destination_url\n/ok,/fine\n/bad*,/x\n"

      post tools_redirects_import_path, params: {file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "r.csv")}

      expect(flash[:notice]).to eq("Import: 1 created, 0 updated, 1 errored — row 3: Source path wildcard `*` is only allowed as a trailing `/*`")
    end

    it "asks for a file" do
      sign_in_as admin

      post tools_redirects_import_path

      expect(flash[:alert]).to eq("Pick a CSV file.")
    end
  end
end
