# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page webhook emission" do
  def make_page(attrs = {})
    Page.create!({
      slug:        "p-#{SecureRandom.hex(3)}",
      title:       "T",
      status:      "draft",
      locale:      "en",
      blocks:      [],
      schema:      {"fields" => []},
      frontmatter: {},
      seo:         {}
    }.merge(attrs))
  end

  before do
    Webhook.create!(
      name:   "any",
      url:    "https://example.com/in",
      events: %w[page.published page.updated page.unpublished page.deleted]
    )
  end

  it "fires page.published when status transitions to published" do
    page = make_page(status: "draft")

    expect {
      page.update!(status: "published")
    }.to have_enqueued_job(Webhook::DeliveryJob).with(
      anything, "page.published", anything
    )
  end

  it "fires page.updated when a published page changes without a status transition" do
    page = make_page(status: "published")

    expect {
      page.update!(title: "Renamed")
    }.to have_enqueued_job(Webhook::DeliveryJob).with(
      anything, "page.updated", anything
    )
  end

  it "fires page.unpublished when leaving published" do
    page = make_page(status: "published")

    expect {
      page.update!(status: "archived")
    }.to have_enqueued_job(Webhook::DeliveryJob).with(
      anything, "page.unpublished", anything
    )
  end

  it "does not fire on draft -> archived (sideways move while never published)" do
    page = make_page(status: "draft")

    expect {
      page.update!(status: "archived")
    }.not_to have_enqueued_job(Webhook::DeliveryJob)
  end

  it "fires page.deleted on destroy" do
    page = make_page(status: "published")

    expect {
      page.destroy!
    }.to have_enqueued_job(Webhook::DeliveryJob).with(
      anything, "page.deleted", anything
    )
  end
end
