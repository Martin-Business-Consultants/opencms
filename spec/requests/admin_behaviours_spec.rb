# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin behaviours", type: :request do
  let(:admin) { create(:user) }

  describe "the audit log's targets" do
    it "links a trashed page to the trash, and a kept one to its editor" do
      kept = Page.create!(slug: "kept", title: "Kept", status: "draft", locale: "en")
      gone = Page.create!(slug: "gone", title: "Gone", status: "draft", locale: "en")
      kept.track_event(:updated)
      gone.track_event(:updated)
      gone.discard!

      expect(AuditLog.find_by(target_id: gone.id, target_type: "Page").target).to eq(gone)

      sign_in_as admin
      get audit_logs_path
      body = response.body.gsub(/\s+/, " ")
      expect(body).to include(%(href="#{edit_page_path("kept")}"), "in the trash", %(href="#{trash_path}"))
    end

    it "reads a target whose type no longer exists as nil" do
      row = AuditLog.create!(action: "gone.thing", target_type: "NoSuchModel", target_id: 1)
      expect(row.target).to be_nil
    end
  end

  describe "a deploy trigger with no provider" do
    it "is recorded as refused, from the admin and the API alike" do
      sign_in_as admin
      post settings_deploy_trigger_path
      post "/api/deploy/trigger", headers: {"Authorization" => "Bearer #{admin.api_token.token}"}, as: :json

      rows = AuditLog.where(action: "settings.deploy_triggered").order(:id).map(&:metadata)
      expect(rows).to eq([{"outcome" => "not_configured"}, {"outcome" => "not_configured", "via" => "api"}])
    end
  end

  describe "bulk actions without JavaScript" do
    it "offers a button per action, posting to that action's own resource" do
      sign_in_as admin
      Page.create!(slug: "one", title: "One", status: "draft", locale: "en")

      get pages_path
      body = response.body

      expect(body).to include("<noscript>", %(formaction="#{pages_bulk_status_changes_path}" name="status" value="published"),
        %(formaction="#{pages_bulk_deletions_path}"), "Delete the ticked pages")
      expect(body).to match(/data-bulk-actions-target="controls" hidden/)
    end

    it "sets the status with only the submitted button's value" do
      sign_in_as admin
      page = Page.create!(slug: "one", title: "One", status: "draft", locale: "en")

      # What a browser posts from the <noscript> button: the form's empty
      # status field first, then the button's own name and value.
      post pages_bulk_status_changes_path, params: "slugs%5B%5D=one&status=&status=published",
        headers: {"CONTENT_TYPE" => "application/x-www-form-urlencoded"}

      expect(page.reload.status).to eq("published")
    end
  end

  describe "deprecated block types in the picker" do
    it "are listed apart, collapsed, and can still be added" do
      BlockType.seed
      deprecated = BlockType.where(deprecated: true).first
      sign_in_as admin
      page = Page.create!(slug: "p", title: "P", status: "draft", locale: "en")

      get edit_page_path(page.path)
      body = response.body

      expect(body).to include(%(class="content-picker__deprecated"), "Deprecated (")
      expect(body.scan(%(data-type="#{deprecated.slug}")).size).to eq(1)

      get new_content_block_path(type: deprecated.slug, scope: "page[blocks]", depth: 0)
      expect(response).to have_http_status(:success)
    end
  end
end
