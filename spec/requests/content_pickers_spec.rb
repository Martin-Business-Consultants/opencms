# frozen_string_literal: true

require "rails_helper"

# The matches a reference or link field's picker offers (content_pickers),
# answered into the picker's turbo-frame.
RSpec.describe "Content pickers", type: :request do
  let(:admin) { create(:user) }

  before do
    sign_in_as admin
    collection = Collection.create!(slug: "partners", name: "Partners", schema: {"fields" => []})
    collection.entries.create!(slug: "acme", title: "Acme Storage", status: "published")
    collection.entries.create!(slug: "bolt", title: "Bolt Movers", status: "published")
    Page.create!(slug: "pricing", title: "Pricing", status: "published", locale: "en")
  end

  it "offers a collection's entries matching what was typed, as their slugs" do
    get content_picker_path(kind: "entries", collection: "partners", q: "acme", frame: "picker_x")

    expect(response.body).to include(%(<turbo-frame id="picker_x">), %(data-value="acme"), "Acme Storage")
    expect(response.body).not_to include("Bolt Movers")
  end

  it "offers pages by slug and any entry as collection/slug for a link" do
    get content_picker_path(kind: "pages", q: "pric")
    expect(response.body).to include(%(data-value="pricing"))

    get content_picker_path(kind: "link_entries", q: "bolt")
    expect(response.body).to include(%(data-value="partners/bolt"))
  end

  it "keeps the frame id to letters, digits, dashes and underscores" do
    get content_picker_path(kind: "pages", frame: %(x"><script>))
    expect(response.body).to include(%(<turbo-frame id="xscript">))
  end

  it "offers no entries to a role without entries:read" do
    sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))

    get content_picker_path(kind: "entries", collection: "partners", q: "acme")
    expect(response.body).not_to include("Acme Storage")
  end
end
