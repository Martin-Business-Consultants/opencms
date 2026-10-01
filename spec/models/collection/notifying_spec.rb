# frozen_string_literal: true

require "rails_helper"

RSpec.describe Collection::Notifying do
  include ActiveJob::TestHelper

  let(:collection) do
    Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []},
      notification_emails: "a@site.test,\n b@site.test", notification_events: %w[entry.published])
  end
  let(:entry) { collection.entries.create!(slug: "hello", title: "Hello", status: "draft") }

  it "reads the recipients and the events it was asked about" do
    expect(collection.notification_email_list).to eq(%w[a@site.test b@site.test])
    expect(collection).to be_notify_on("entry.published")
    expect(collection).not_to be_notify_on("entry.created")
  end

  it "queues the email only for an event subscribed to" do
    expect { collection.notify_subscribers_later(entry, "entry.published", {id: entry.id}) }
      .to have_enqueued_job(Collection::NotifySubscribersJob).with(collection.id, entry.id, "entry.published", {id: entry.id})
    expect { collection.notify_subscribers_later(entry, "entry.created", {}) }.not_to have_enqueued_job
  end

  it "emails the subscribers, even about an entry since trashed" do
    entry.discard!

    expect { collection.notify_subscribers_now(entry.id, "entry.published", {id: entry.id}) }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq(%w[a@site.test b@site.test])
  end

  it "rejects events it doesn't know" do
    collection.notification_events = %w[entry.published entry.exploded]

    expect(collection).not_to be_valid
    expect(collection.errors[:notification_events]).to eq(["unknown: entry.exploded"])
  end
end
