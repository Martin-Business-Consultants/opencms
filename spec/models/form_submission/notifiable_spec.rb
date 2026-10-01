# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormSubmission::Notifiable do
  include ActiveJob::TestHelper

  let(:form) do
    Form.create!(slug: "contact", title: "Contact", status: "published", notify_webhook_url: "https://hooks.test/forms",
      fields: [{"name" => "email", "label" => "Email", "type" => "email", "required" => true}])
  end

  before do
    form.emails.find_by(kind: "notification").update!(enabled: true, recipients: "ops@x.test", subject: "New")
    Cms::Plugins.switch!(:forms, on: true)
  end

  it "is queued when a submission arrives" do
    expect { form.submissions.create!(data: {"email" => "a@b.test"}, meta: {}, ip: "1.2.3.4") }
      .to have_enqueued_job(FormSubmission::NotificationJob)
  end

  it "emails the recipients and posts the form's webhook" do
    submission = form.submissions.create!(data: {"email" => "a@b.test"}, meta: {}, ip: "1.2.3.4")
    posted = []
    allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, request|
      posted << JSON.parse(request.body)
      Net::HTTPOK.new("1.1", "200", "OK")
    end

    expect { submission.notify_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq(["ops@x.test"])
    expect(posted.sole.dig("submission", "data")).to eq("email" => "a@b.test")
  end

  it "posts only the mapped keys when the webhook selects fields" do
    form.update!(title: "Contact", webhook_body: {"mode" => "fields", "mappings" => [
      {"key" => "email_address", "source" => "field:email"},
      {"key" => "from", "source" => "meta:form_slug"},
      {"key" => "lead_source", "source" => "custom", "value" => "Website: {{form_title}} ({{email}})"}
    ]})
    submission = form.submissions.create!(data: {"email" => "a@b.test"}, meta: {}, ip: "1.2.3.4")
    posted = []
    allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, request|
      posted << JSON.parse(request.body)
      Net::HTTPOK.new("1.1", "200", "OK")
    end

    submission.notify_now

    expect(posted.sole).to eq("email_address" => "a@b.test", "from" => "contact", "lead_source" => "Website: Contact (a@b.test)")
  end
end
