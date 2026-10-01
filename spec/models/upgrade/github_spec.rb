# frozen_string_literal: true

require "rails_helper"

RSpec.describe Upgrade::Github do
  let(:upgrade) { Upgrade.create!(requested_by: create(:user), from_version: Cms::VERSION, to_version: "99.0.0", via: "github") }

  around do |example|
    with_env("CMS_GITHUB_TOKEN" => "ghp_deploy", "CMS_DEPLOY_DESTINATION" => "acme", "CMS_DEPLOY_WORKFLOW" => nil,
      "CMS_RELEASES_REPO" => nil) { example.run }
  end

  # Answers each request with the response for the first pattern its path
  # matches, and keeps the requests for the example to look at.
  def github(responses)
    @requests = []
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) do |request|
      @requests << request
      responses.find { |pattern, _| request.path.match?(pattern) }&.last || Net::HTTPNotFound.new("1.1", "404", "Not Found")
    end
  end

  def ok(body)
    Net::HTTPOK.new("1.1", "200", "OK").tap { |response| allow(response).to receive(:body).and_return(JSON.generate(body)) }
  end

  it "starts the Deploy workflow for the release's tag and destination, and keeps the run" do
    github(%r{/dispatches\z} => ok(workflow_run_id: 77, html_url: "https://github.com/runs/77"))

    described_class.new(upgrade).start

    request = @requests.sole
    expect(request).to be_a(Net::HTTP::Post)
    expect(request.path).to eq("/repos/Martin-Business-Consultants/opencms/actions/workflows/deploy.yml/dispatches")
    expect(request["Authorization"]).to eq("Bearer ghp_deploy")
    expect(JSON.parse(request.body)).to eq("ref" => "v99.0.0", "return_run_details" => true,
      "inputs" => {"version" => "v99.0.0", "destination" => "acme", "upgrade" => "#{Site.host} ##{upgrade.id}"})
    expect(upgrade.reload).to have_attributes(external_id: "77", external_url: "https://github.com/runs/77")
  end

  it "finds its run by the marker in the title when GitHub didn't return it" do
    github(
      %r{/runs\?} => ok(workflow_runs: [
        {id: 5, html_url: "https://github.com/runs/5", display_title: "Deploy v99.0.0 (other.example ##{upgrade.id})"},
        {id: 6, html_url: "https://github.com/runs/6", display_title: "Deploy v99.0.0 (#{Site.host} ##{upgrade.id})"}
      ]),
      %r{/actions/runs/6\z} => ok(status: "in_progress", conclusion: nil)
    )

    described_class.new(upgrade).check

    expect(@requests.first.path).to include("event=workflow_dispatch")
    expect(upgrade.reload).to have_attributes(external_id: "6", status: "running")
  end

  it "fails the update when the run ended without deploying" do
    upgrade.update!(external_id: "6")
    github(%r{/actions/runs/6\z} => ok(status: "completed", conclusion: "startup_failure"))

    described_class.new(upgrade).check

    expect(upgrade.reload).to be_failed
    expect(upgrade.message).to eq("The deploy on GitHub ended startup failure. Its log says why.")
  end

  it "leaves a successful run for the new version's boot to settle" do
    upgrade.update!(external_id: "6")
    github(%r{/actions/runs/6\z} => ok(status: "completed", conclusion: "success"))

    described_class.new(upgrade).check

    expect(upgrade.reload).to be_running
  end

  it "fails the update with GitHub's reason when the workflow can't be started" do
    refused = Net::HTTPForbidden.new("1.1", "403", "Forbidden")
    allow(refused).to receive(:body).and_return(JSON.generate(message: "Resource not accessible by personal access token"))
    github(%r{/dispatches\z} => refused)

    upgrade.run

    expect(upgrade.reload).to be_failed
    expect(upgrade.message).to eq("GitHub refused: Resource not accessible by personal access token.")
  end

  it "says what's missing before it can be used" do
    expect(described_class.unavailable_reason).to be_nil

    with_env("CMS_DEPLOY_DESTINATION" => " ") { expect(described_class.unavailable_reason).to match(/CMS_DEPLOY_DESTINATION/) }
    with_env("CMS_GITHUB_TOKEN" => nil, "CMS_RELEASES_TOKEN" => "read") do
      expect(described_class.unavailable_reason).to match(/CMS_GITHUB_TOKEN/)
    end
  end
end
