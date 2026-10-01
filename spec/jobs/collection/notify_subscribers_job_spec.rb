# frozen_string_literal: true

require "rails_helper"

RSpec.describe Collection::NotifySubscribersJob do
  let(:collection) do
    Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []},
      notification_emails: "a@site.test", notification_events: %w[entry.published])
  end
  let(:entry) { collection.entries.create!(slug: "hello", title: "Hello", status: "published") }

  it "emails the collection's subscribers" do
    expect { described_class.perform_now(collection.id, entry.id, "entry.published", {"id" => entry.id}) }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
  end

  it "does nothing for a collection since deleted" do
    expect { described_class.perform_now(0, entry.id, "entry.published", {}) }
      .not_to change { ActionMailer::Base.deliveries.size }
  end

  # The old name and its trailing tenant argument, for jobs queued before the
  # rename. Goes with the shim.
  it "still runs a job queued under its old name" do
    expect { NotifyCollectionEventJob.perform_now(collection.id, entry.id, "entry.published", {"id" => entry.id}, "cms") }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
  end
end
