# frozen_string_literal: true

require "rails_helper"

# The review gate, on the record: what a write by someone who can't publish
# comes to, whichever of the admin, the API or an agent made it.
RSpec.describe Revisable do
  let(:writer) { create(:user, admin: false) }
  let(:live) { Page.create!(slug: "live", title: "Live", status: "published", locale: "en") }
  let(:draft) { Page.create!(slug: "draft", title: "Draft", status: "draft", locale: "en") }

  it "gates a live record for someone who can't publish, never a draft or a publisher" do
    expect(live.review_gated?(can_publish: false)).to be(true)
    expect(live.review_gated?(can_publish: true)).to be(false)
    expect(draft.review_gated?(can_publish: false)).to be(false)
  end

  it "reads liveness from the database, so assigning a status first doesn't change it" do
    live.status = "draft"
    expect(live.review_gated?(can_publish: false)).to be(true)
  end

  it "gates any saved global: they have no draft state" do
    global = Global.create!(slug: "nav", name: "Nav", data: {})
    expect(global.review_gated?(can_publish: false)).to be(true)
  end

  it "files a revision and leaves the record as it is" do
    proposal = live.propose({"title" => "Edited"}, by: writer, source: "ui")

    expect(proposal).to be_proposed
    expect(proposal.revision).to have_attributes(payload: {"title" => "Edited"}, source: "ui", author: writer)
    expect(live.reload.title).to eq("Live")
  end

  it "says unchanged when nothing a revision may carry would change" do
    expect(live.propose({"title" => "Live", "status" => "draft"}, by: writer, source: "api").outcome).to eq(:unchanged)
    expect(Revision.count).to eq(0)
  end

  it "names the pending revision when one is already waiting" do
    first = live.propose({"title" => "One"}, by: writer, source: "api").revision
    second = live.propose({"title" => "Two"}, by: writer, source: "api")

    expect(second.outcome).to eq(:conflict)
    expect(second.revision).to eq(first)
    expect(second.error).to be_a(ActiveRecord::RecordInvalid)
  end
end
