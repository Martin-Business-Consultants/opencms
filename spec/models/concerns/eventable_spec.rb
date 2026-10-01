# frozen_string_literal: true

require "rails_helper"

RSpec.describe Eventable do
  let(:user) { create(:user) }
  let(:page) { Page.create!(slug: "about", title: "About", status: "draft", locale: "en") }

  before do
    Current.session = user.sessions.create!
    Current.remote_ip = "203.0.113.9"
    Current.user_agent = "Spec/1.0"
  end

  it "records the event as an audit row, prefixed and attributed to whoever is acting" do
    log = page.track_event(:deleted, path: "about", status: "draft")

    expect(log).to have_attributes(action: "page.deleted", target: page, actor: user,
      metadata: {"path" => "about", "status" => "draft"}, ip: "203.0.113.9", user_agent: "Spec/1.0")
  end

  it "marks events made over the API, last, as they have always been recorded" do
    Current.via = "api"

    expect(page.track_event(:purged, path: "about").metadata).to eq("path" => "about", "via" => "api")
  end

  it "names no target for an event about a set of records" do
    log = Page.track_event(:bulk_deleted, count: 2, paths: %w[a b])

    expect(log).to have_attributes(action: "page.bulk_deleted", target: nil, metadata: {"count" => 2, "paths" => %w[a b]})
  end

  it "announces the event in-process" do
    heard = []
    subscription = ActiveSupport::Notifications.subscribe("event.cms") { |*, payload| heard << payload }

    page.track_event(:updated, path: "about", status: "draft")

    expect(heard).to contain_exactly(a_hash_including(action: "page.updated", target: page,
      particulars: {path: "about", status: "draft"}))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  it "is system when nobody is acting, as in a job" do
    Current.reset

    expect(page.track_event(:updated, path: "about", status: "draft")).to have_attributes(actor: nil, actor_label: "system")
  end
end
