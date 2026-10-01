# frozen_string_literal: true

require "rails_helper"

# A list's search box (?s=), as WordPress's: it searches the whole list on the
# server, keeps the list's other filters, and says what it searched for.
RSpec.describe "List search", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  # The rows the list shows (not the New page dialog's parent list).
  def row_text = Nokogiri::HTML5(response.body).css("table.data-table tbody").text

  def make_page(slug, title, status: "published")
    Page.create!(slug: slug, title: title, status: status, locale: "en")
  end

  it "finds pages by title or path across the whole list" do
    make_page("pricing", "Plans and pricing")
    make_page("about", "About us")

    get pages_path(s: "pric")

    expect(response.body).to include("Search results for “<strong>pric</strong>”")
    expect(row_text).to include("Plans and pricing")
    expect(row_text).not_to include("About us")
  end

  it "keeps the list's other filters in the search form and alongside the results" do
    make_page("draft-pricing", "Draft pricing", status: "draft")
    make_page("live-pricing", "Live pricing")

    get pages_path(status: "draft", s: "pricing")

    expect(row_text).to include("Draft pricing")
    expect(row_text).not_to include("Live pricing")
    expect(response.body).to include(%(name="status" value="draft"))
  end

  it "treats % and _ as the characters they are" do
    make_page("fifty", "50% off")
    make_page("plain", "Fifty off")

    get pages_path(s: "50%")

    expect(row_text).to include("50% off")
    expect(row_text).not_to include("Fifty off")
  end

  it "searches users, redirects and the audit log too" do
    create(:user, name: "Grace Hopper", email: "grace@example.test")
    Redirect.create!(source_path: "/old-pricing", destination_url: "/pricing")
    Redirect.create!(source_path: "/elsewhere", destination_url: "/x")

    get users_path(s: "hopper")
    expect(response.body).to include("Grace Hopper")

    get tools_redirects_path(s: "pricing")
    expect(row_text).to include("/old-pricing")
    expect(row_text).not_to include("/elsewhere")

    get audit_logs_path(s: "zzz-nothing")
    expect(response).to have_http_status(:success)
  end
end
