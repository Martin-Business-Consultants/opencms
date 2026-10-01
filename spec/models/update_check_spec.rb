# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateCheck do
  def respond_with(response)
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) { |request| @request = request; response }
  end

  def release(tag)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(JSON.generate(tag_name: tag, html_url: "https://github.com/x/releases/#{tag}",
      body: "Fixes things.", published_at: "2026-09-30T12:00:00Z"))
    response
  end

  it "stores the latest release and says when it is newer" do
    respond_with(release("v99.0.0"))

    UpdateCheckJob.perform_now

    expect(@request.path).to eq("/repos/Martin-Business-Consultants/opencms/releases/latest")
    expect(described_class.latest_version).to eq("99.0.0")
    expect(described_class.latest_tag).to eq("v99.0.0")
    expect(described_class.release_url).to end_with("v99.0.0")
    expect(described_class.notes).to eq("Fixes things.")
    expect(described_class.published_at).to eq(Time.utc(2026, 9, 30, 12))
    expect(described_class.checked_at).to be_within(1.minute).of(Time.current)
    expect(described_class).to be_update_available
  end

  it "isn't news when the release is this version" do
    respond_with(release("v#{Cms::VERSION}"))

    described_class.check_now

    expect(described_class).not_to be_update_available
  end

  it "keeps quiet when GitHub can't be reached or says no" do
    allow(Net::HTTP).to receive(:new).and_raise(SocketError, "offline")
    expect { described_class.check_now }.not_to raise_error

    respond_with(Net::HTTPNotFound.new("1.1", "404", "Not Found"))
    expect { described_class.check_now }.not_to raise_error
    expect(described_class.latest_version).to be_nil
  end

  it "says why when asked to check now" do
    allow(Net::HTTP).to receive(:new).and_raise(SocketError, "offline")
    expect { described_class.check_now! }.to raise_error(UpdateCheck::Github::Error, /Couldn't reach GitHub/)

    not_found = Net::HTTPNotFound.new("1.1", "404", "Not Found")
    allow(not_found).to receive(:body).and_return(JSON.generate(message: "Not Found"))
    respond_with(not_found)
    expect { described_class.check_now! }.to raise_error(UpdateCheck::Github::Error, /no releases or workflow for Martin-Business-Consultants\/opencms/)
  end

  it "reads a private repository with whichever token it has" do
    respond_with(release("v99.0.0"))

    with_env("CMS_RELEASES_TOKEN" => "read-only", "CMS_GITHUB_TOKEN" => nil) { described_class.check_now! }
    expect(@request["Authorization"]).to eq("Bearer read-only")

    with_env("CMS_RELEASES_TOKEN" => nil, "CMS_GITHUB_TOKEN" => "deploys") { described_class.check_now! }
    expect(@request["Authorization"]).to eq("Bearer deploys")
  end

  it "skips the daily check with CMS_UPDATE_CHECK=false, but still settles updates" do
    allow(Net::HTTP).to receive(:new)
    expect(Upgrade).to receive(:settle_running)

    with_env("CMS_UPDATE_CHECK" => "false") { UpdateCheckJob.perform_now }

    expect(Net::HTTP).not_to have_received(:new)
  end
end
