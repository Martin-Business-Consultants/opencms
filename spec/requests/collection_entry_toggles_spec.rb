# frozen_string_literal: true

require "rails_helper"

# Inline boolean toggles on the collection entries table
# (Collections::Entries::FlagsController). Deliberately narrow: boolean schema
# fields only, and a MERGE into frontmatter (the entry form replaces the blob
# wholesale, which an inline toggle cannot do without destroying the entry's
# other fields).
RSpec.describe "Collection entry inline toggles", type: :request do
  # Reset the tables these examples touch (children first). Sessions
  # especially: `sign_in_as` writes its cookie into the shared
  # `env_config` jar, which outlives the example — leaving the row behind would
  # keep later examples silently signed in.
  before do
    CollectionEntry.destroy_all
    Collection.destroy_all
    Session.delete_all
  end

  let(:user) { create(:user) }

  let(:collection) do
    Collection.create!(
      slug: "specials",
      name: "Specials",
      schema: {"fields" => [
        {"name" => "description", "label" => "Description", "type" => "text"},
        {"name" => "day", "label" => "Day of week", "type" => "select",
         "options" => %w[Monday Tuesday]},
        {"name" => "active", "label" => "Active", "type" => "boolean"},
        {"name" => "featured", "label" => "Featured", "type" => "boolean"}
      ]}
    )
  end

  let(:entry) do
    collection.entries.create!(
      slug: "beer-brats",
      title: "Beer Brats",
      status: "published",
      locale: "en",
      frontmatter: {
        "description" => "Brats poached in cream ale",
        "day"         => "Monday",
        "active"      => true
      }
    )
  end

  # The table's switch for one field on one entry: its label and pressed state.
  def switch(field, slug: entry.slug)
    row = Nokogiri::HTML(response.body).at_css("#" + ActionView::RecordIdentifier.dom_id(CollectionEntry.find_by!(slug: slug)))
    row.css("form").find { |form| form.at_css("input[name=field][value='#{field}']") }&.at_css("button")
  end

  def toggle(field:, value:, slug: entry.slug)
    patch collection_entry_flag_url(collection.slug, slug),
          params: {field: field, value: value}
  end

  describe "PATCH /collections/:collection_slug/entries/:entry_slug/flag" do
    it "redirects unauthenticated callers to sign-in" do
      entry
      toggle(field: "active", value: false)
      expect(response).to redirect_to(sign_in_url)
    end

    context "when signed in" do
      before { sign_in_as user }

      it "flips the field off" do
        toggle(field: "active", value: false)

        expect(response).to redirect_to(collection_entries_path(collection.slug))
        expect(entry.reload.frontmatter["active"]).to be false
      end

      it "flips the field on" do
        entry.update!(frontmatter: entry.frontmatter.merge("active" => false))

        toggle(field: "active", value: true)
        expect(entry.reload.frontmatter["active"]).to be true
      end

      # The whole reason this endpoint exists rather than reusing #update.
      it "preserves every other frontmatter key" do
        toggle(field: "active", value: false)

        fm = entry.reload.frontmatter
        expect(fm["description"]).to eq "Brats poached in cream ale"
        expect(fm["day"]).to eq "Monday"
      end

      it "sets a boolean that was previously absent without touching siblings" do
        expect(entry.frontmatter).not_to have_key("featured")

        toggle(field: "featured", value: true)

        fm = entry.reload.frontmatter
        expect(fm["featured"]).to be true
        expect(fm["active"]).to be true
        expect(fm["day"]).to eq "Monday"
      end

      it "coerces string values sent over the wire" do
        toggle(field: "active", value: "false")
        expect(entry.reload.frontmatter["active"]).to be false

        toggle(field: "active", value: "true")
        expect(entry.reload.frontmatter["active"]).to be true
      end

      # Validation keeps strings out going forward, but a row written before the
      # field was switched to `boolean` in the schema editor can still hold one.
      # `update_column` reproduces that legacy row by skipping validation.
      it "reads a stringy stored value as false" do
        entry.update_column(:frontmatter, entry.frontmatter.merge("active" => "false"))

        get collection_entries_url(collection.slug)
        expect(response).to have_http_status(:success)

        expect(switch("active")["aria-pressed"]).to eq "false"
      end

      it "refuses a field that is not declared boolean in the schema" do
        toggle(field: "description", value: true)

        expect(entry.reload.frontmatter["description"]).to eq "Brats poached in cream ale"
      end

      it "refuses a field that is not in the schema at all" do
        toggle(field: "nope", value: true)

        expect(entry.reload.frontmatter).not_to have_key("nope")
      end

      it "refuses a blank field name" do
        toggle(field: "", value: true)
        expect(response).to have_http_status(:redirect)
      end

      it "404s for an unknown entry" do
        entry
        toggle(field: "active", value: false, slug: "does-not-exist")
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /collections/:collection_slug/entries" do
    before { sign_in_as user }

    it "renders" do
      entry
      get collection_entries_url(collection.slug)
      expect(response).to have_http_status(:success)
    end

    it "gives each boolean field a column of switches" do
      entry
      get collection_entries_url(collection.slug)

      headers = Nokogiri::HTML(response.body).css("thead th").map(&:text)
      expect(headers).to include("Active", "Featured")
      expect(headers).not_to include("Description", "Day of week")
    end

    it "shows each switch's stored state and flips it to the other" do
      entry
      get collection_entries_url(collection.slug)

      expect(switch("active")["aria-pressed"]).to eq "true"
      expect(switch("featured")["aria-pressed"]).to eq "false"
      # Not the whole blob — the list doesn't carry description/day.
      expect(response.body).not_to include("Brats poached in cream ale")
    end
  end
end
