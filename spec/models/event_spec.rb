# frozen_string_literal: true

require "rails_helper"

RSpec.describe Event do
  describe ".record" do
    it "writes the audit row for whoever is acting and publishes it in-process" do
      user = create(:user)
      Current.session = user.sessions.create!
      heard = []
      subscriber = ActiveSupport::Notifications.subscribe("event.cms") { |*, payload| heard << payload }

      row = described_class.record("settings.brand_updated", fields_set: ["audience"])

      expect(row).to have_attributes(action: "settings.brand_updated", actor: user, metadata: {"fields_set" => ["audience"]})
      expect(heard).to contain_exactly(hash_including(action: "settings.brand_updated", particulars: {fields_set: ["audience"]}))
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "marks events made through the API" do
      Current.via = "api"

      expect(described_class.record("plugin.enabled", plugin: "hello").metadata).to eq("plugin" => "hello", "via" => "api")
    end

    it "takes an actor the event names instead of Current's" do
      user = create(:user)

      expect(described_class.record("session.created", target: user, actor: user)).to have_attributes(actor: user, target: user)
    end
  end

  describe ".announce" do
    it "delivers a webhook event to every active webhook that wants it, and publishes it in-process" do
      wants = Webhook.create!(name: "a", url: "https://a.example.com", events: ["page.published"])
      Webhook.create!(name: "b", url: "https://b.example.com", events: ["page.updated"])
      heard = []
      subscriber = ActiveSupport::Notifications.subscribe("page.published.cms") { |*, payload| heard << payload }

      expect { described_class.announce("page.published", {id: 7}) }
        .to have_enqueued_job(Webhook::DeliveryJob).exactly(:once).with(wants.id, "page.published", {id: 7})
      expect(heard).to eq([{event: "page.published", data: {id: 7}}])
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "only publishes an event webhooks don't carry, naming the record" do
      Webhook.create!(name: "a", url: "https://a.example.com", events: Webhook.events)
      page = Page.create!(slug: "p", title: "P", status: "draft", locale: "en")
      heard = []
      subscriber = ActiveSupport::Notifications.subscribe("page.created.cms") { |*, payload| heard << payload }

      expect { described_class.announce("page.created", {id: page.id}, subject: page) }.not_to have_enqueued_job(Webhook::DeliveryJob)
      expect(heard).to eq([{event: "page.created", data: {id: page.id}, record: page}])
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "hands the announcement to the subject's own subscribers" do
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []},
        notification_emails: "editor@site.test", notification_events: ["entry.published"])
      entry = collection.entries.create!(slug: "a", title: "A", status: "draft")

      expect { described_class.announce("entry.published", {id: entry.id}, subject: entry) }
        .to have_enqueued_job(Collection::NotifySubscribersJob).with(collection.id, entry.id, "entry.published", {id: entry.id})
    end

    it "asks for a site rebuild on content events, not on a form submission" do
      allow(Deploys).to receive(:schedule_later)

      described_class.announce("global.updated", {slug: "nav"})
      described_class.announce("submission.created", {id: 1})

      expect(Deploys).to have_received(:schedule_later).once.with(reason: "global.updated")
    end
  end
end
