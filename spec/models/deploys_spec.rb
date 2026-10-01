# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deploys do
  def http_stub(response)
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) { |request| @request = request; response }
    http
  end

  describe ".current" do
    it "keeps an install with a build hook on the build hook" do
      Setting.set("deploy", {"url" => "https://hooks.example.com/x"})

      expect(described_class.current).to be_a(Deploys::BuildHook)
      expect(described_class.current.target).to eq("hooks.example.com")
    end

    it "defaults to GitHub otherwise" do
      expect(described_class.current).to be_a(Deploys::Github)
      expect(described_class.current).not_to be_configured
    end

    it "uses the provider Settings › Deploy chose" do
      Setting.set("deploy", {"url" => "https://hooks.example.com/x", "provider" => "github"})

      expect(described_class.current).to be_a(Deploys::Github)
    end
  end

  describe Deploys::Github do
    before { Setting.set("github", {"token" => "ghp_secret", "frontend_github_repo" => "acme/acme-site"}) }

    it "sends a repository_dispatch to the site's repo" do
      http_stub(Net::HTTPNoContent.new("1.1", "204", "No Content"))

      attempt = Deploys::Github.new.fire(reason: "page.published")

      expect(attempt.status).to eq("success")
      expect(attempt.http_status).to eq(204)
      expect(@request.path).to eq("/repos/acme/acme-site/dispatches")
      expect(@request["Authorization"]).to eq("Bearer ghp_secret")
      expect(JSON.parse(@request.body)).to include("event_type" => "cms-publish",
        "client_payload" => {"reason" => "page.published", "site" => Site.key})
    end

    it "records a refused dispatch as a failure" do
      http_stub(Net::HTTPNotFound.new("1.1", "404", "Not Found"))

      expect(Deploys::Github.new.fire(reason: "manual").status).to eq("failure")
    end

    it "runs through Deploys::TriggerJob and its log" do
      Setting.set("deploy", {"provider" => "github", "scheduled_at" => "t"})
      http_stub(Net::HTTPNoContent.new("1.1", "204", "No Content"))

      Deploys::TriggerJob.perform_now("t", "manual")

      expect(Setting.get("deploy")["log"].first).to include("status" => "success", "http_status" => 204, "reason" => "manual")
    end
  end

  # The job and the stamp it checks share one timestamp. Two Time.current
  # calls a few microseconds apart made every manual deploy skip itself.
  it "fires a manual deploy in real time rather than skipping it as superseded" do
    Setting.set(Deploys::SETTING_KEY, "url" => "https://build.example/hook", "provider" => "build_hook")
    allow_any_instance_of(Deploys::BuildHook).to receive(:fire).and_return(Deploys::Attempt.new(status: "success", http_status: 200))

    job = Deploys.trigger_later
    scheduled_at = job.arguments.first
    expect(Setting.get(Deploys::SETTING_KEY)["scheduled_at"]).to eq(scheduled_at)

    Deploys::TriggerJob.perform_now(*job.arguments)
    expect(Setting.get(Deploys::SETTING_KEY)["last_status"]).to eq("success")
  end
end
