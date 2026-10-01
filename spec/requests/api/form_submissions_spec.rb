# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API form submissions", type: :request do
  let!(:form) do
    Form.create!(slug: "contact", title: "Contact", status: "published",
                 fields: [{"name" => "email", "label" => "Email", "type" => "email"}])
  end

  let(:path) { "/api/forms/contact/submissions" }

  def turnstile_answer(success:)
    Net::HTTPOK.new("1.1", "200", "OK").tap { |res|
      allow(res).to receive(:body).and_return(JSON.generate({"success" => success}))
    }
  end

  # Captures the request sent to Cloudflare and answers with `answer`.
  def stub_turnstile(answer)
    sent = {}
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) { |req| sent[:request] = req; answer }
    allow(Net::HTTP).to receive(:start) { |host, *_args, **_opts, &blk|
      sent[:host] = host
      blk.call(http)
    }
    sent
  end

  context "with no Turnstile secret configured" do
    it "accepts a submission without any captcha token" do
      expect(Net::HTTP).not_to receive(:start)

      expect {
        post path, params: {email: "a@b.com"}
      }.to change(FormSubmission, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end

  context "with a Turnstile secret configured" do
    before do
      Setting.set("forms_settings", {"captcha_provider" => "turnstile", "turnstile_secret_key" => "sekret"})
    end

    it "rejects a submission with no token" do
      expect(Net::HTTP).not_to receive(:start)

      expect {
        post path, params: {email: "a@b.com"}
      }.not_to change(FormSubmission, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq({"error" => "captcha_failed"})
    end

    it "verifies the cf-turnstile-response token with Cloudflare, passing remoteip" do
      sent = stub_turnstile(turnstile_answer(success: true))

      expect {
        post path, params: {:email => "a@b.com", "cf-turnstile-response" => "tok-1"},
                   headers: {"REMOTE_ADDR" => "203.0.113.7"}
      }.to change(FormSubmission, :count).by(1)
      expect(response).to have_http_status(:created)

      expect(sent[:host]).to eq("challenges.cloudflare.com")
      expect(sent[:request].path).to eq("/turnstile/v0/siteverify")
      expect(URI.decode_www_form(sent[:request].body).to_h)
        .to eq({"secret" => "sekret", "response" => "tok-1", "remoteip" => "203.0.113.7"})
    end

    it "accepts the token as turnstile_token too" do
      sent = stub_turnstile(turnstile_answer(success: true))

      post path, params: {email: "a@b.com", turnstile_token: "tok-2"}

      expect(response).to have_http_status(:created)
      expect(URI.decode_www_form(sent[:request].body).to_h["response"]).to eq("tok-2")
    end

    it "rejects a token Cloudflare says is invalid" do
      stub_turnstile(turnstile_answer(success: false))

      expect {
        post path, params: {:email => "a@b.com", "cf-turnstile-response" => "bad"}
      }.not_to change(FormSubmission, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq({"error" => "captcha_failed"})
    end

    it "fails closed when Cloudflare can't be reached" do
      allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

      post path, params: {:email => "a@b.com", "cf-turnstile-response" => "tok"}

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq({"error" => "captcha_failed"})
    end

    it "still short-circuits on the honeypot before checking the captcha" do
      expect(Net::HTTP).not_to receive(:start)

      expect {
        post path, params: {:email => "a@b.com", Form::HONEYPOT_FIELD => "bot"}
      }.not_to change(FormSubmission, :count)
      expect(response).to have_http_status(:created)
    end

    it "skips verification when another captcha provider is selected" do
      Setting.set("forms_settings", {"captcha_provider" => "none"})
      expect(Net::HTTP).not_to receive(:start)

      post path, params: {email: "a@b.com"}

      expect(response).to have_http_status(:created)
    end
  end
end
