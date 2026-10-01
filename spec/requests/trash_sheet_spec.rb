# frozen_string_literal: true

require "rails_helper"

# The trash's list opens what an item was in a sheet, with who deleted it,
# and restores or deletes it from there.
RSpec.describe "Trash sheet", type: :request do
  let(:admin) { create(:user, name: "Robin") }

  before { sign_in_as admin }

  it "lists trashed items that open into the sheet, and shows one there" do
    page = Page.create!(slug: "old", title: "Old page", status: "draft", locale: "en")
    delete page_path(page.path)

    get trash_path
    expect(response.body).to include('turbo-frame id="trash_item"', 'data-turbo-frame="trash_item"', "Old page")

    get trash_item_path("page", page.id), headers: {"Turbo-Frame" => "trash_item"}
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Old page", "/old", "Restore", "Delete permanently")
    expect(response.body).to include("by #{admin.email}")

    post trash_item_restoration_path("page", page.id)
    expect(page.reload.discarded?).to be(false)
  end
end
