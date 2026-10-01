# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Trash", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as user }

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

  describe "GET /trash" do
    it "lists discarded records" do
      page = make_page(title: "Trashed")
      page.discard!

      get trash_url
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Trashed", "Restore")
    end
  end

  describe "POST /trash/:kind/:id/restoration" do
    it "restores a discarded page" do
      page = make_page
      page.discard!

      post trash_item_restoration_url("page", page.id)
      expect(response).to redirect_to(trash_path)
      expect(Page.find(page.id).kept?).to eq(true)
    end
  end

  describe "DELETE /trash/:kind/:id" do
    it "permanently deletes a discarded page" do
      page = make_page
      page.discard!

      expect {
        delete trash_item_url("page", page.id)
      }.to change { Page.with_discarded.where(id: page.id).count }.from(1).to(0)
    end
  end

  it "blocks readers without trash:write from restoring" do
    page = make_page; page.discard!

    reader_role = create(:role, permissions: ["trash:read"])
    reader      = create(:user, admin: false, role: reader_role)
    sign_in_as reader

    post trash_item_restoration_url("page", page.id)
    expect(response).to redirect_to(dashboard_path)
    expect(Page.with_discarded.find(page.id).discarded?).to eq(true)
  end
end
