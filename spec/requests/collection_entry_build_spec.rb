# frozen_string_literal: true

require "rails_helper"

# The Build board: two columns standing for one boolean frontmatter field, so
# dragging a card across IS the edit, plus inline controls on the cards in the
# "on" column. A card control goes through Collections::Entries::CardFields and
# a drop through Collections::Entries::Placements; both merge into the
# frontmatter rather than replace it, which a card can't post whole.
RSpec.describe "Collection entry Build board", type: :request do
  before do
    CollectionEntry.destroy_all
    Collection.destroy_all
    Session.delete_all
  end

  let(:user) { create(:user) }

  let(:fields) do
    [
      {"name" => "description", "label" => "Description", "type" => "text"},
      {"name" => "day", "label" => "Day of week", "type" => "select",
       "options" => %w[Monday Tuesday Wednesday]},
      {"name" => "price", "label" => "Price", "type" => "string"},
      {"name" => "servings", "label" => "Servings", "type" => "integer"},
      {"name" => "active", "label" => "Active", "type" => "boolean"},
      {"name" => "featured", "label" => "Featured", "type" => "boolean"}
    ]
  end

  let(:build_config) do
    {"field" => "active", "off_label" => "Resting", "on_label" => "On the menu",
     "card_fields" => %w[day price]}
  end

  let(:collection) do
    Collection.create!(slug: "specials", name: "Specials",
                       schema: {"fields" => fields}, build_config: build_config)
  end

  let!(:on_entry) do
    collection.entries.create!(
      slug: "beer-brats", title: "Beer Brats", status: "published", locale: "en",
      frontmatter: {"description" => "Brats poached in cream ale", "day" => "Monday", "active" => true}
    )
  end

  let!(:off_entry) do
    collection.entries.create!(
      slug: "fish-fry", title: "Fish Fry", status: "draft", locale: "en",
      frontmatter: {"description" => "Friday cod", "active" => false}
    )
  end

  def board
    Nokogiri::HTML(response.body).at_css("#build_board")
  end

  def column(label)
    board.css("section").find { |section| section["aria-label"] == label }
  end

  def card(slug)
    board.at_css("[data-id='#{slug}']")
  end

  def write(field:, value:, slug: on_entry.slug)
    patch collection_entry_card_field_url(collection.slug, slug),
          params: {field: field, value: value}
  end

  def move(on:, slug: off_entry.slug)
    post collection_entry_placement_url(collection.slug, slug), params: {column: on ? "on" : "off"}
  end

  # A board that carries the entry's status and a second boolean across with
  # its column field.
  def carrying_board
    collection.update!(build_config: build_config.merge(
      "also_fields" => ["featured"], "also_publish" => true
    ))
  end

  describe "GET /collections/:collection_slug/entries/build" do
    it "redirects unauthenticated callers to sign-in" do
      get build_collection_entries_url(collection.slug)
      expect(response).to redirect_to(sign_in_url)
    end

    context "when signed in" do
      before { sign_in_as user }

      it "draws the configured columns with each card in its place" do
        get build_collection_entries_url(collection.slug)
        expect(response).to have_http_status(:success)

        expect(column("Resting").at_css("[data-id='fish-fry']")).to be_present
        expect(column("On the menu").at_css("[data-id='beer-brats']")).to be_present
        expect(card("beer-brats")["draggable"]).to eq "true"
      end

      it "says what a move carries across with the column field" do
        carrying_board
        get build_collection_entries_url(collection.slug)

        expect(response.body).to include("turns on Active and Featured and publishes the entry")
      end

      # Only what the board draws — the card controls, on the right-hand
      # column's cards. The rest of the frontmatter belongs to the entry form.
      it "puts the card controls on the right-hand cards only" do
        get build_collection_entries_url(collection.slug)

        on_card = card("beer-brats")
        expect(on_card.css("input[name=field]").map { it["value"] }).to eq %w[day price]
        expect(on_card.at_css("select[name=value] option[selected]").text).to eq "Monday"
        expect(card("fish-fry").css("input[name=field]")).to be_empty
        expect(response.body).not_to include("Brats poached in cream ale")
      end

      it "reads a stringy stored boolean as false" do
        on_entry.update_column(:frontmatter, on_entry.frontmatter.merge("active" => "false"))

        get build_collection_entries_url(collection.slug)

        expect(column("Resting").at_css("[data-id='beer-brats']")).to be_present
      end

      # Without a field there are no columns, so send the editor to where one
      # is chosen rather than rendering an empty board.
      it "sends a collection with no board to its schema page" do
        collection.update!(build_config: {})

        get build_collection_entries_url(collection.slug)
        expect(response).to redirect_to(collection_schema_path(collection.slug))
      end
    end
  end

  describe "PATCH /collections/:collection_slug/entries/:entry_slug/card_field" do
    it "redirects unauthenticated callers to sign-in" do
      write(field: "day", value: "Tuesday")
      expect(response).to redirect_to(sign_in_url)
    end

    context "when signed in" do
      before { sign_in_as user }

      # The drag itself.
      it "flips the column field when a card crosses the board" do
        write(field: "active", value: true, slug: off_entry.slug)

        expect(response).to redirect_to(build_collection_entries_path(collection.slug))
        expect(off_entry.reload.frontmatter["active"]).to be true
      end

      it "sets an inline select value without disturbing the rest" do
        write(field: "day", value: "Wednesday")

        fm = on_entry.reload.frontmatter
        expect(fm["day"]).to eq "Wednesday"
        expect(fm["description"]).to eq "Brats poached in cream ale"
        expect(fm["active"]).to be true
      end

      it "coerces a number sent over the wire" do
        write(field: "servings", value: "4")
        expect(on_entry.reload.frontmatter["servings"]).to eq 4
      end

      # Clearing a card control shouldn't leave "" in the JSON the site reads —
      # the site checks for the key's presence.
      it "removes the key when the value is blank" do
        write(field: "day", value: "")

        expect(on_entry.reload.frontmatter).not_to have_key("day")
      end

      it "refuses a field that can't be edited on a card" do
        write(field: "description", value: "rewritten")

        expect(on_entry.reload.frontmatter["description"]).to eq "Brats poached in cream ale"
      end

      it "refuses a field that is not in the schema at all" do
        write(field: "nope", value: "x")
        expect(on_entry.reload.frontmatter).not_to have_key("nope")
      end

      # The schema's own validation still applies — the board is a shortcut
      # into the entry, not a way around it.
      it "refuses a select value outside the declared options" do
        write(field: "day", value: "Caturday")

        expect(on_entry.reload.frontmatter["day"]).to eq "Monday"
      end

      it "404s for an unknown entry" do
        write(field: "day", value: "Tuesday", slug: "does-not-exist")
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /collections/:collection_slug/entries/:entry_slug/placement" do
    it "redirects unauthenticated callers to sign-in" do
      move(on: true)
      expect(response).to redirect_to(sign_in_url)
    end

    context "when signed in" do
      before { sign_in_as user }

      it "flips the column field when a card crosses the board" do
        move(on: true)

        expect(response).to redirect_to(build_collection_entries_path(collection.slug))
        expect(off_entry.reload.frontmatter["active"]).to be true
      end

      it "leaves the rest of the frontmatter alone" do
        move(on: true)
        expect(off_entry.reload.frontmatter["description"]).to eq "Friday cod"
      end

      # The whole point of the extras: one drag, everything the column means.
      it "carries the other booleans and the status across with it" do
        carrying_board
        move(on: true)

        off_entry.reload
        expect(off_entry.frontmatter["active"]).to be true
        expect(off_entry.frontmatter["featured"]).to be true
        expect(off_entry.status).to eq "published"
      end

      # Mirrored, so the right-hand column is a complete statement about what
      # is live — a card on the left is off, and not published.
      it "turns them all off again on the way back" do
        carrying_board
        on_entry.update!(frontmatter: on_entry.frontmatter.merge("featured" => true))

        move(on: false, slug: on_entry.slug)

        on_entry.reload
        expect(on_entry.frontmatter["active"]).to be false
        expect(on_entry.frontmatter["featured"]).to be false
        expect(on_entry.status).to eq "draft"
      end

      # A publish is a publish, however it was made — an editor auditing what
      # went live shouldn't have to know the board exists.
      it "records a move that publishes as a publish" do
        carrying_board
        move(on: true)

        log = AuditLog.order(:id).last
        expect(log.action).to eq "entry.published"
        expect(log.metadata["fields"]).to eq %w[active featured]
      end

      it "leaves the status alone on a board that doesn't publish" do
        move(on: true, slug: on_entry.slug)
        expect(on_entry.reload.status).to eq "published"

        move(on: false, slug: on_entry.slug)
        expect(on_entry.reload.status).to eq "published"
      end

      it "404s for an unknown entry" do
        move(on: true, slug: "does-not-exist")
        expect(response).to have_http_status(:not_found)
      end
    end

    # A board that publishes is a publishing tool. Writing frontmatter is
    # `entries:write`; putting something in front of visitors isn't.
    context "when the user can write but not publish" do
      let(:editor) do
        create(:user, admin: false,
                      role: create(:role, permissions: %w[entries:read entries:write]))
      end

      before do
        carrying_board
        sign_in_as editor
      end

      it "refuses the move and changes nothing" do
        move(on: true)

        off_entry.reload
        expect(off_entry.frontmatter["active"]).to be false
        expect(off_entry.status).to eq "draft"
      end

      it "doesn't offer the drag" do
        get build_collection_entries_url(collection.slug)
        expect(card("fish-fry")["draggable"]).to eq "false"
        expect(response.body).to include("which needs publish access")
      end

      # The cards still work — only the column itself is out of reach.
      it "still allows an inline card edit" do
        write(field: "day", value: "Tuesday")
        expect(on_entry.reload.frontmatter["day"]).to eq "Tuesday"
      end
    end
  end

  # A drop from the board itself answers with the board, morphed back in.
  describe "a drop from the board" do
    before { sign_in_as user }

    it "answers with the board and the flash as turbo streams" do
      post collection_entry_placement_url(collection.slug, off_entry.slug),
           params: {column: "on"}, headers: {"Accept" => "text/vnd.turbo-stream.html"}

      expect(response.media_type).to eq "text/vnd.turbo-stream.html"
      expect(response.body).to include('target="build_board"', 'method="morph"', "Fish Fry moved to On the menu")
      expect(off_entry.reload.frontmatter["active"]).to be true
    end
  end

  # The board is configured where the rest of the entry shape is.
  describe "PATCH /collections/:collection_slug/schema" do
    before { sign_in_as user }

    # The schema form posts the whole shape every time, so mirror that.
    def save_schema(build)
      patch collection_schema_url(collection.slug),
            params: {collection: {fields: fields, enable_blocks: false, build_config: build}}
    end

    it "stores the posted board config" do
      save_schema({field: "active", on_label: "On the menu", card_fields: ["day"]})

      expect(collection.reload.build_settings)
        .to eq("field" => "active", "on_label" => "On the menu", "card_fields" => ["day"])
    end

    # How the form switches the board back off: clear the field.
    it "drops the whole config when no field is chosen" do
      save_schema({field: "", on_label: "On the menu", card_fields: ["day"]})

      expect(collection.reload.build_board?).to be false
    end

    it "rejects a config the schema can't support" do
      save_schema({field: "description"})

      expect(response).to have_http_status(:unprocessable_content)
      expect(collection.reload.build_settings["field"]).to eq "active"
    end
  end
end
