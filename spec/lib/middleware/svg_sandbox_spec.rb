# frozen_string_literal: true

require "rails_helper"

RSpec.describe SvgSandbox do
  def call(headers)
    app = ->(_env) { [200, headers, ["body"]] }
    described_class.new(app).call(Rack::MockRequest.env_for("/x"))
  end

  it "adds the sandbox CSP and nosniff to SVG responses" do
    _, headers, = call("content-type" => "image/svg+xml; charset=utf-8")

    expect(headers["content-security-policy"]).to eq(described_class::CONTENT_SECURITY_POLICY)
    expect(headers["x-content-type-options"]).to eq("nosniff")
  end

  it "replaces a CSP set further down the stack" do
    _, headers, = call(Rack::Headers["content-type" => "image/svg+xml", "content-security-policy" => "script-src *"])

    expect(headers["content-security-policy"]).to eq(described_class::CONTENT_SECURITY_POLICY)
  end

  it "matches a mixed-case header name" do
    _, headers, = call("Content-Type" => "IMAGE/SVG+XML")

    expect(headers["content-security-policy"]).to include("sandbox")
  end

  it "leaves other responses untouched" do
    original = {"content-type" => "image/png"}
    _, headers, = call(original)

    expect(headers).to eq("content-type" => "image/png")
  end
end
