# frozen_string_literal: true

require "rails_helper"

RSpec.describe Report::Runnable do
  before do
    Report.delete_all
    Setting.delete_all
    switch_plugin(:local_marketing, on: true)
  end

  def configure!
    Setting.set_secret("reporting", dataforseo_login: "u", dataforseo_password: "p")
    Setting.set("reporting", "business_name" => "Acme", "domain" => "acme.com",
      "location_name" => "Austin,Texas,United States", "tracked_keywords" => ["storage"])
  end

  describe ".queue" do
    it "refuses without a credential, and names what's missing" do
      expect(Report.queue("ranked_keywords").error).to match(/DataForSEO credentials/)

      configure!
      Setting.set("reporting", "domain" => "")
      expect(Report.queue("ranked_keywords").error).to match(/needs domain/)
      expect(Report.count).to eq(0)
    end

    it "queues one run and never a second while it's in flight" do
      configure!

      first = nil
      expect { first = Report.queue("ranked_keywords") }.to have_enqueued_job(Report::RunJob)
      again = Report.queue("ranked_keywords")

      expect(first).to be_queued
      expect(again).to be_skipped
      expect(again.report).to eq(first.report)
      expect(Report.in_flight.count).to eq(1)
    end

    # The Run button, a baseline, a setup and the weekly refresh all queue
    # through here, so all of them are in the audit log.
    it "records report.queued once per report it queues, and not for a skip" do
      configure!

      Report.queue("ranked_keywords")
      Report.queue("ranked_keywords")

      rows = AuditLog.where(action: "report.queued")
      expect(rows.count).to eq(1)
      expect(rows.first.metadata).to include("kind" => "ranked_keywords")
    end

    it "queues several against one profile" do
      configure!

      results = Report.queue_all(%w[ranked_keywords nope])

      expect(results.map(&:first)).to eq(%w[ranked_keywords nope])
      expect(results.last.last.error).to eq("Unknown report: nope")
    end
  end

  describe "#run_now" do
    it "leaves a report that is no longer queued alone" do
      report = Report.create!(kind: "ranked_keywords", status: "complete")
      expect(DataForSeo::Client).not_to receive(:from_settings)

      report.run_now

      expect(report.reload.status).to eq("complete")
    end

    it "fails the report with a message that names it" do
      report = Report.create!(kind: "ranked_keywords")
      allow(DataForSeo::Client).to receive(:from_settings).and_raise(NoMethodError, "boom")

      report.run_now

      expect(report.reload.status).to eq("failed")
      expect(report.error).to start_with("#{report.title} failed:")
    end
  end

  it "keeps the old job name running what was queued under it" do
    expect(RunReportJob.superclass).to eq(Report::RunJob)
  end
end
