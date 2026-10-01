# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Tools do
  let(:agent) do
    Agent.create!(name: "Editor", instructions: "Edit things.",
      capability_keys: %w[manifest read_pages write_pages recommend])
  end
  let(:run) { agent.dispatch! }

  describe ".for_run" do
    it "builds tools from the capability keys frozen into the brief" do
      names = described_class.for_run(run).map(&:name)

      expect(names).to include("site_manifest", "list_pages", "get_page", "update_page", "file_recommendation")
      expect(names).not_to include("publish_page", "set_entry_status")
    end
  end

  describe "UpdatePage" do
    let(:tool) { described_class::UpdatePage.new(run) }

    it "edits a draft in place" do
      page = Page.create!(slug: "notes", title: "Notes", status: "draft")

      result = tool.call("path" => page.path, "title" => "Better notes")

      expect(result[:status]).to eq("updated")
      expect(page.reload.title).to eq("Better notes")
    end

    it "files a revision instead of touching a published page" do
      page = Page.create!(slug: "live", title: "Live", status: "published", published_at: Time.current)

      result = tool.call("path" => page.path, "title" => "Sneaky rewrite")

      expect(result[:status]).to eq("proposed")
      expect(page.reload.title).to eq("Live")
      revision = Revision.find(result[:revision_id])
      expect(revision.payload).to eq("title" => "Sneaky rewrite")
      expect(revision.source).to eq("agent")
    end

    it "records the proposal as the editor and the API do, naming the run" do
      page = Page.create!(slug: "live", title: "Live", status: "published", published_at: Time.current)

      result = tool.call("path" => page.path, "title" => "Sneaky rewrite")

      row = AuditLog.where(action: "revision.proposed").last
      expect(row).to be_present
      expect(row.target_id).to eq(result[:revision_id])
      expect(row.metadata).to include("revisable" => "Page##{page.id}", "fields" => ["title"], "agent_run" => run.id)
      expect(row.actor_id).to eq(run.triggered_by&.id)
    end

    it "never publishes a draft, whatever the write carries" do
      page = Page.create!(slug: "notes", title: "Notes", status: "draft")

      tool.send(:gated_write, page, {title: "Notes, revised", status: "published", publish_at: 1.day.from_now})

      expect(page.reload).to have_attributes(title: "Notes, revised", status: "draft", publish_at: nil)
    end

    it "answers with an error, not an exception, for a missing page" do
      expect(tool.call("path" => "nope")[:error]).to include("nope")
    end
  end

  describe "FileRecommendation" do
    let(:tool) { described_class::FileRecommendation.new(run) }

    it "files a finding attributed to the run" do
      result = tool.call("kind" => "metadata", "title" => "Titles too long", "impact" => 4)

      rec = Recommendation.find(result[:recommendation_id])
      expect(rec.agent_run_id).to eq(run.id)
      expect(rec.impact).to eq(4)
    end

    it "refuses findings past the run's budget" do
      cap = Agents::Budget.from(run.brief["budget"]).proposals
      cap.times { |i| tool.call("kind" => "metadata", "title" => "Finding #{i}") }

      expect(tool.call("kind" => "metadata", "title" => "One too many")[:error]).to include("budget")
    end
  end
end
