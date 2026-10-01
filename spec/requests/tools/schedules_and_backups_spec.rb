# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# Tools › Schedules and Tools › Backup. Their API halves are
# /api/tools/recurring_tasks and /api/tools/backup (the `cms` CLI's).
RSpec.describe "Tools › Schedules and Backup", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user) }

  before { sign_in_as admin }

  describe "schedules" do
    it "lists every recipe, set up or not, and opens one's settings in the sheet" do
      RecurringTask.create!(recipe_key: "broken_link_scan", cron: "0 4 * * *", enabled: true,
        last_run_at: 1.hour.ago, last_status: "ok", last_summary: "Checked 12 links")

      get tools_recurring_tasks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Trash purge", "Broken-link scan", "0 4 * * *", 'data-turbo-frame="schedule_sheet"')

      get edit_tools_recurring_task_path("broken_link_scan"), headers: {"Turbo-Frame" => "schedule_sheet"}
      expect(response.body).to include("Checked 12 links", "Max links to check", 'name="task[params][max_links]"')

      get edit_tools_recurring_task_path("broken_link_scan")
      expect(response.body).to include('data-dialog-auto-open-value="true"', "Max links to check")
    end

    it "saves a schedule, with its settings as numbers" do
      patch tools_recurring_task_path("broken_link_scan"),
        params: {task: {enabled: "1", cron: "30 2 * * *", params: {max_links: "50", timeout_seconds: ""}}}

      expect(response).to redirect_to(tools_recurring_tasks_path)
      task = RecurringTask.find_by(recipe_key: "broken_link_scan")
      expect(task).to have_attributes(enabled: true, cron: "30 2 * * *", params: {"max_links" => 50})
      expect(AuditLog.last.action).to eq("recurring_task.updated")
    end

    it "shows the list again with the error for a bad cron" do
      patch tools_recurring_task_path("broken_link_scan"), params: {task: {enabled: "1", cron: "not cron"}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That didn’t work", 'data-dialog-auto-open-value="true"')
    end

    it "runs one now, setting it up at its defaults first" do
      post tools_recurring_task_run_path("trash_purge")

      task = RecurringTask.find_by(recipe_key: "trash_purge")
      expect(task.cron).to eq(RecurringTasks::Recipes::TrashPurge.default_cron)
      expect(RecurringTask::RunJob).to have_been_enqueued.with(task.id)
      expect(flash[:notice]).to eq("Trash purge queued.")
    end

    it "refuses a recipe it doesn't know" do
      post tools_recurring_task_run_path("nope")

      expect(flash[:alert]).to eq("Unknown recipe.")
    end
  end

  describe "backup" do
    around do |example|
      Dir.mktmpdir do |dir|
        ENV["CMS_BACKUP_DIR"] = dir
        example.run
      ensure
        ENV.delete("CMS_BACKUP_DIR")
      end
    end

    it "says what a backup holds and lists the automatic ones" do
      File.write(File.join(ENV["CMS_BACKUP_DIR"], "cms-data-20260901-120000.tar.gz"), "x" * 2048)
      File.write(File.join(ENV["CMS_BACKUP_DIR"], "unrelated.txt"), "no")
      Page.create!(slug: "about", title: "About", status: "draft", locale: "en")

      get tools_backup_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 pages", "cms-data-20260901-120000.tar.gz", "2 KB")
      expect(response.body).not_to include("unrelated.txt")
    end

    it "downloads an automatic backup, but only one that's listed" do
      File.write(File.join(ENV["CMS_BACKUP_DIR"], "cms-data-20260901-120000.tar.gz"), "archive")

      get tools_backup_archive_path("cms-data-20260901-120000.tar.gz")
      expect(response.body).to eq("archive")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(AuditLog.last.action).to eq("data_backup.downloaded")

      get tools_backup_archive_path("cms-data-20260902-120000.tar.gz")
      expect(response).to have_http_status(:not_found)
    end

    it "downloads a backup of the site now" do
      post tools_backup_path

      expect(response.media_type).to eq("application/gzip")
      expect(AuditLog.last.action).to eq("site_backup.exported")
    end

    it "is refused without tools:use" do
      sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))

      get tools_backup_path

      expect(response).to have_http_status(:redirect)
    end
  end
end
