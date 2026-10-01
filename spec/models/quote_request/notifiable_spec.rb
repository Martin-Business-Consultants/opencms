# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteRequest::Notifiable do
  let(:quote) { QuoteRequest.create!(customer_name: "Ann", customer_email: "ann@x.test", items: [{"title" => "Oak"}]) }

  it "emails the shop's recipients" do
    Setting.set("commerce", {"notification_recipients" => "shop@site.test, owner@site.test"})

    expect { quote.notify_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq(%w[shop@site.test owner@site.test])
  end

  it "stays quiet when there's nobody to tell" do
    Setting.set("commerce", {"notification_recipients" => ""})

    expect { quote.notify_now }.not_to change { ActionMailer::Base.deliveries.size }
  end
end
