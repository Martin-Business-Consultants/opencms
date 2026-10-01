# frozen_string_literal: true

require "rails_helper"

# The whole reason this class exists is that DataForSEO answers 200 to most
# failures and puts the real outcome in `status_code`, twice. These specs are
# mostly about the ways a "successful" HTTP response is actually a failure.
RSpec.describe DataForSeo::Client do
  before { Setting.delete_all }

  let(:client) { described_class.new(login: "user@example.com", password: "secret") }

  def stub_http(body:, klass: Net::HTTPSuccess, code: "200")
    captured = nil
    response = Class.new(klass).new("1.1", code, "OK").tap do |r|
      payload = body.is_a?(String) ? body : JSON.generate(body)
      r.define_singleton_method(:body) { payload }
      r.define_singleton_method(:code) { code }
    end

    allow_any_instance_of(Net::HTTP).to receive(:request) do |_self, req|
      captured = req
      response
    end

    -> { captured }
  end

  def envelope(tasks:, status_code: 20_000)
    {"version" => "0.1.0", "status_code" => status_code,
     "status_message" => "Ok.", "tasks" => tasks}
  end

  def task(result:, status_code: 20_000, cost: 0.02)
    {"id" => "abc", "status_code" => status_code, "status_message" => "Ok.",
     "cost" => cost, "result" => result}
  end

  describe "#post" do
    it "sends the task as a one-element array with basic auth" do
      request = stub_http(body: envelope(tasks: [task(result: [{"total_count" => 5}])]))

      client.post("dataforseo_labs/google/ranked_keywords/live", target: "acme.com")

      expect(JSON.parse(request.call.body)).to eq([{"target" => "acme.com"}])
      expect(request.call["Authorization"]).to start_with("Basic ")
      expect(request.call.path).to eq("/v3/dataforseo_labs/google/ranked_keywords/live")
    end

    it "drops nil values rather than sending them as null" do
      request = stub_http(body: envelope(tasks: [task(result: [])]))

      client.post("some/path", target: "acme.com", location_name: nil)

      expect(JSON.parse(request.call.body).first.keys).to eq(["target"])
    end

    it "returns the task's result array and what it actually cost" do
      stub_http(body: envelope(tasks: [task(result: [{"a" => 1}], cost: 0.0375)]))

      response = client.post("some/path", {})

      expect(response.result).to eq([{"a" => 1}])
      expect(response.cost).to eq(0.0375)
      expect(response.first).to eq({"a" => 1})
    end

    it "raises on a request-level error even though the HTTP status is 200" do
      stub_http(body: envelope(tasks: [], status_code: 40_200))

      expect { client.post("some/path", {}) }
        .to raise_error(DataForSeo::Error, /40200/)
    end

    it "raises on a task-level error even though the envelope says OK" do
      stub_http(body: envelope(tasks: [task(result: nil, status_code: 40_501)]))

      expect { client.post("some/path", {}) }
        .to raise_error(DataForSeo::Error, /40501/)
    end

    it "raises NotConfigured on a 401, which carries no JSON envelope" do
      stub_http(body: "Unauthorized", klass: Net::HTTPUnauthorized, code: "401")

      expect { client.post("some/path", {}) }
        .to raise_error(DataForSeo::NotConfigured, /rejected the credentials/)
    end

    it "raises rather than exploding on a non-JSON body" do
      stub_http(body: "<html>502 Bad Gateway</html>")

      expect { client.post("some/path", {}) }.to raise_error(DataForSeo::Error, /non-JSON/)
    end
  end

  describe "#post_many" do
    it "keeps the correspondence with what was sent, nil for a failed task" do
      stub_http(body: envelope(tasks: [
        task(result: [{"k" => "a"}]),
        task(result: nil, status_code: 40_501),
        task(result: [{"k" => "c"}])
      ]))

      responses = client.post_many("serp/google/organic/live/advanced",
                                   [{keyword: "a"}, {keyword: "b"}, {keyword: "c"}])

      expect(responses.length).to eq(3)
      expect(responses[0].first).to eq({"k" => "a"})
      expect(responses[1]).to be_nil
      expect(responses[2].first).to eq({"k" => "c"})
    end

    it "makes no request at all for an empty task list" do
      expect_any_instance_of(Net::HTTP).not_to receive(:request)

      expect(client.post_many("some/path", [])).to eq([])
    end
  end

  describe ".configured? and .from_settings" do
    it "is false until both halves of the credential are present" do
      expect(described_class).not_to be_configured

      Setting.set_secret("reporting", dataforseo_login: "user@example.com")
      expect(described_class).not_to be_configured

      Setting.set_secret("reporting", dataforseo_password: "secret")
      expect(described_class).to be_configured
    end

    it "raises NotConfigured rather than returning nil" do
      expect { described_class.from_settings }
        .to raise_error(DataForSeo::NotConfigured, /Settings → Reporting/)
    end

    it "routes to the sandbox host when the setting says so" do
      Setting.set_secret("reporting", dataforseo_login: "u", dataforseo_password: "p")
      Setting.set("reporting", sandbox: true)

      expect(described_class.from_settings.host).to eq("sandbox.dataforseo.com")
    end
  end
end
