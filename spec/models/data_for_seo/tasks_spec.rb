# frozen_string_literal: true

require "rails_helper"

# The task-based half of the client: post, then poll. The statuses that
# mean "not yet" must not read as errors, and the one that means "created"
# must not read as a failure to create.
RSpec.describe DataForSeo::Client, "task-based endpoints" do
  let(:client) { described_class.new(login: "u", password: "p") }

  def stub_http(body)
    response = Class.new(Net::HTTPSuccess).new("1.1", "200", "OK")
    payload = JSON.generate(body)
    response.define_singleton_method(:body) { payload }
    response.define_singleton_method(:code) { "200" }
    captured = nil
    allow_any_instance_of(Net::HTTP).to receive(:request) { |_s, req| captured = req; response }
    -> { captured }
  end

  def envelope(task) = {"status_code" => 20_000, "status_message" => "Ok.", "tasks" => [task]}

  it "accepts 20100 Task Created from task_post and returns the id and the charge" do
    req = stub_http(envelope("id" => "abc", "status_code" => 20_100, "status_message" => "Task Created.", "cost" => 0.00075))

    posted = client.post_task("business_data/google/reviews", keyword: "Acme", depth: 50)

    expect(req.call.path).to eq("/v3/business_data/google/reviews/task_post")
    expect(posted).to eq(id: "abc", cost: 0.00075)
  end

  it "raises when task_post itself fails" do
    stub_http(envelope("id" => "abc", "status_code" => 40_501, "status_message" => "Invalid Field: 'depth'."))
    expect { client.post_task("business_data/google/reviews", {}) }.to raise_error(DataForSeo::Error, /40501/)
  end

  it "returns nil from task_get while the task is queued or handed to a worker" do
    stub_http(envelope("id" => "abc", "status_code" => 40_602, "status_message" => "Task In Queue.", "result" => nil))
    expect(client.task_get("business_data/google/reviews", "abc")).to be_nil

    stub_http(envelope("id" => "abc", "status_code" => 40_601, "status_message" => "Task Handed.", "result" => nil))
    expect(client.task_get("business_data/google/reviews", "abc")).to be_nil
  end

  it "returns the result once the task is done" do
    req = stub_http(envelope("id" => "abc", "status_code" => 20_000, "cost" => 0.0, "result" => [{"reviews_count" => 3}]))

    response = client.task_get("business_data/google/reviews", "abc")

    expect(req.call.path).to eq("/v3/business_data/google/reviews/task_get/abc")
    expect(response.first).to eq("reviews_count" => 3)
  end

  it "raises on any other task_get status rather than looping forever" do
    stub_http(envelope("id" => "abc", "status_code" => 40_400, "status_message" => "Not Found."))
    expect { client.task_get("business_data/google/reviews", "abc") }.to raise_error(DataForSeo::Error, /40400/)
  end
end
