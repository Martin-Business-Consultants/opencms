# frozen_string_literal: true

require "rails_helper"

RSpec.describe Upgrade::Hoster do
  let(:upgrade) { Upgrade.create!(requested_by: create(:user), from_version: Cms::VERSION, to_version: "99.0.0", via: "hoster") }

  around do |example|
    with_env("CMS_HOSTER_URL" => "https://hoster.test/", "CMS_HOSTER_TOKEN" => "hst_write",
      "CMS_HOSTER_ENVIRONMENT_ID" => "12") { example.run }
  end

  # Answers each request with the response for the first pattern its path
  # matches, and keeps the requests for the example to look at.
  def hoster(responses)
    @requests = []
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) do |request|
      @requests << request
      responses.find { |pattern, _| request.path.match?(pattern) }&.last || Net::HTTPNotFound.new("1.1", "404", "Not Found")
    end
  end

  def answer(klass, code, body)
    klass.new("1.1", code, "").tap { |response| allow(response).to receive(:body).and_return(JSON.generate(body)) }
  end

  def ok(body) = answer(Net::HTTPOK, "200", body)

  it "proposes deploying the release's tag to this install's environment, and keeps the change request" do
    hoster(%r{/change_requests\z} => answer(Net::HTTPAccepted, "202",
      change_request: {id: 31, status: "pending", url: "https://hoster.test/1/change_requests/31"}))

    described_class.new(upgrade).start

    request = @requests.sole
    expect(request).to be_a(Net::HTTP::Post)
    expect(request.path).to eq("/api/v1/change_requests")
    expect(request["Authorization"]).to eq("Bearer hst_write")
    expect(JSON.parse(request.body)).to eq("action_name" => "environments.deploy",
      "params" => {"environment_id" => "12", "ref" => "v99.0.0"})
    expect(upgrade.reload).to have_attributes(external_id: "change_request:31",
      external_url: "https://hoster.test/1/change_requests/31")
  end

  it "waits, without timing out, while the deploy awaits approval" do
    upgrade.update!(external_id: "change_request:31", created_at: 2.days.ago)
    hoster(%r{/change_requests/31\z} => ok(change_request: {id: 31, status: "pending"}))

    upgrade.settle

    expect(upgrade.reload).to be_running
    expect(described_class.new(upgrade)).to be_awaiting_approval
  end

  it "follows the deployment once Hoster applies the change" do
    upgrade.update!(external_id: "change_request:31")
    hoster(
      %r{/change_requests/31\z} => ok(change_request: {id: 31, status: "applied", result: {deployment_id: 8}}),
      %r{/deployments/8\z} => ok(deployment: {id: 8, status: "running", url: "https://hoster.test/1/deployments/8"})
    )

    described_class.new(upgrade).check

    expect(upgrade.reload).to have_attributes(external_id: "deployment:8",
      external_url: "https://hoster.test/1/deployments/8", status: "running")
  end

  it "fails the update when the deploy is turned down" do
    upgrade.update!(external_id: "change_request:31")
    hoster(%r{/change_requests/31\z} => ok(change_request: {id: 31, status: "rejected", decided_by: "Ted"}))

    described_class.new(upgrade).check

    expect(upgrade.reload).to be_failed
    expect(upgrade.message).to eq("The deploy was turned down in Hoster by Ted.")
  end

  it "fails the update when the deployment fails" do
    upgrade.update!(external_id: "deployment:8")
    hoster(%r{/deployments/8\z} => ok(deployment: {id: 8, status: "failed", error: "Kamal exited 1"}))

    described_class.new(upgrade).check

    expect(upgrade.reload.message).to eq("The deploy in Hoster failed: Kamal exited 1.")
  end

  it "times out from when the deploy started, not from when it was asked for" do
    upgrade.update!(external_id: "deployment:8", created_at: 2.days.ago)
    upgrade.update_column(:updated_at, (Upgrade::TIMEOUT + 1.minute).ago)

    upgrade.settle

    expect(upgrade.reload).to be_failed
    expect(upgrade.message).to start_with("No word after")
  end

  it "says which setting is missing" do
    with_env("CMS_HOSTER_ENVIRONMENT_ID" => nil) do
      expect(described_class.unavailable_reason).to include("CMS_HOSTER_ENVIRONMENT_ID")
    end
  end

  it "is how a production install with a Hoster token updates" do
    allow(Rails.env).to receive(:production?).and_return(true)
    with_env("CMS_UPDATES" => nil) { expect(Upgrade.via).to eq("hoster") }
  end

  it "names Hoster's refusal of the token" do
    hoster(%r{/change_requests\z} => answer(Net::HTTPUnauthorized, "401", error: "Send a Hoster API token"))

    expect { described_class.new(upgrade).start }.to raise_error(described_class::Error, /refused CMS_HOSTER_TOKEN/)
  end
end
