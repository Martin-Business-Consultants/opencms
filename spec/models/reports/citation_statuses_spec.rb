# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::CitationStatuses do
  before { Setting.delete_all }

  it "keeps one row per directory, with who said so, and records it" do
    user = create(:user)
    Current.user = user if Current.respond_to?(:user=)

    expect {
      described_class.update("yelp.com", status: "submitted", note: "  sent  ", by: user)
    }.to change(AuditLog, :count).by(1)

    expect(described_class.all["yelp.com"]).to include("status" => "submitted", "note" => "sent", "updated_by" => user.email)
    expect(AuditLog.last).to have_attributes(action: "citation.status_updated")
    expect(described_class.known_status?("live")).to be(true)
    expect(described_class.known_status?("nope")).to be(false)
  end
end
