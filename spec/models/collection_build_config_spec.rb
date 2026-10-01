# frozen_string_literal: true

require "rails_helper"

# The Build board's per-collection config: which boolean field the two columns
# stand for, what they're called, and which other fields a card edits in place.
RSpec.describe Collection, "#build_config" do
  def make(build_config)
    described_class.create!(
      slug:         "specials-#{SecureRandom.hex(3)}",
      name:         "Specials",
      build_config: build_config,
      schema:       {"fields" => [
        {"name" => "active", "label" => "Active", "type" => "boolean"},
        {"name" => "featured", "label" => "Featured", "type" => "boolean"},
        {"name" => "day", "label" => "Day of week", "type" => "select",
         "options" => %w[Monday Tuesday]},
        {"name" => "price", "type" => "string"},
        {"name" => "description", "type" => "text"}
      ]}
    )
  end

  describe "validation" do
    it "accepts a boolean field with card fields" do
      collection = make({"field" => "active", "card_fields" => ["day"]})
      expect(collection.build_board?).to be true
    end

    it "treats an empty config as no board" do
      collection = make({})
      expect(collection.build_board?).to be false
    end

    it "refuses a field the schema doesn't declare" do
      collection = described_class.new(slug: "x", name: "X", schema: {"fields" => []},
                                       build_config: {"field" => "nope"})
      collection.valid?
      expect(collection.errors[:build_config].join).to match(/not in this collection's schema/)
    end

    # Two columns are two states — anything but a boolean would need more.
    it "refuses a field that isn't a boolean" do
      collection = described_class.new(
        slug: "x", name: "X",
        schema: {"fields" => [{"name" => "day", "type" => "select", "options" => ["Monday"]}]},
        build_config: {"field" => "day"}
      )
      collection.valid?
      expect(collection.errors[:build_config].join).to match(/must be a boolean/)
    end

    it "refuses a card field that can't fit on a card" do
      collection = described_class.new(
        slug: "x", name: "X",
        schema: {"fields" => [
          {"name" => "active", "type" => "boolean"},
          {"name" => "description", "type" => "text"}
        ]},
        build_config: {"field" => "active", "card_fields" => ["description"]}
      )
      collection.valid?
      expect(collection.errors[:build_config].join).to match(/cannot be edited on a card/)
    end

    it "refuses card fields with no field to hang them on" do
      collection = described_class.new(slug: "x", name: "X", schema: {"fields" => []},
                                       build_config: {"card_fields" => ["day"]})
      collection.valid?
      expect(collection.errors[:build_config]).to be_present
    end

    it "accepts other booleans carried across with the column field" do
      collection = make({"field" => "active", "also_fields" => ["featured"], "also_publish" => true})
      expect(collection.build_also_fields.map { |f| f["name"] }).to eq(["featured"])
      expect(collection.build_publishes?).to be true
    end

    # Two columns are two states, so anything riding along has to be a boolean
    # for the same reason the column field does.
    it "refuses a carried field that isn't a boolean" do
      collection = described_class.new(
        slug: "x", name: "X",
        schema: {"fields" => [
          {"name" => "active", "type" => "boolean"},
          {"name" => "price", "type" => "string"}
        ]},
        build_config: {"field" => "active", "also_fields" => ["price"]}
      )
      collection.valid?
      expect(collection.errors[:build_config].join).to match(/must be a boolean to move with the columns/)
    end

    it "refuses publishing with no field to hang it on" do
      collection = described_class.new(slug: "x", name: "X", schema: {"fields" => []},
                                       build_config: {"also_publish" => true})
      collection.valid?
      expect(collection.errors[:build_config]).to be_present
    end
  end

  describe "#build_move_fields" do
    it "leads with the column field and adds what follows it" do
      collection = make({"field" => "active", "also_fields" => ["featured"]})
      expect(collection.build_move_fields.map { |f| f["name"] }).to eq(%w[active featured])
    end

    it "never lists the column field twice" do
      collection = make({"field" => "active", "also_fields" => %w[active featured]})
      expect(collection.build_move_fields.map { |f| f["name"] }).to eq(%w[active featured])
    end

    it "drops a carried field the schema no longer declares" do
      collection = make({"field" => "active", "also_fields" => ["featured"]})
      collection.update_column(:schema, {"fields" => [{"name" => "active", "type" => "boolean"}]})

      expect(collection.reload.build_move_fields.map { |f| f["name"] }).to eq(["active"])
    end
  end

  describe "#build_card_fields" do
    it "resolves names to field definitions" do
      collection = make({"field" => "active", "card_fields" => %w[day price]})
      expect(collection.build_card_fields.map { |f| f["name"] }).to eq(%w[day price])
    end

    # The schema can move on long after the board was set up; a board pointing
    # at a field that's gone should lose that card control, not blow up.
    it "drops names the schema no longer declares" do
      collection = make({"field" => "active", "card_fields" => %w[day price]})
      collection.update_column(:schema, {"fields" => [{"name" => "active", "type" => "boolean"}]})

      expect(collection.reload.build_card_fields).to eq([])
    end

    it "never includes the field the columns already stand for" do
      collection = make({"field" => "active", "card_fields" => %w[active day]})
      expect(collection.build_card_fields.map { |f| f["name"] }).to eq(["day"])
    end
  end

  describe "#build_column_labels" do
    it "falls back when the labels are blank" do
      expect(make({"field" => "active"}).build_column_labels)
        .to eq("off" => "Off", "on" => "On")
    end

    it "uses what the collection was given" do
      collection = make({"field" => "active", "off_label" => "Resting", "on_label" => "On the menu"})
      expect(collection.build_column_labels)
        .to eq("off" => "Resting", "on" => "On the menu")
    end
  end

  describe ".normalize_build_config" do
    it "drops everything when no field is named" do
      expect(described_class.normalize_build_config({"off_label" => "Resting"})).to eq({})
    end

    # Nothing extra is the default, so an empty list and a false flag aren't
    # worth storing — a plain board reads back exactly as it always did.
    it "omits the extras when the board carries nothing else" do
      expect(
        described_class.normalize_build_config(
          "field" => "active", "also_fields" => [], "also_publish" => false
        )
      ).to eq("field" => "active", "card_fields" => [])
    end

    it "keeps the extras when the board carries something" do
      expect(
        described_class.normalize_build_config(
          "field" => "active", "also_fields" => [" featured ", "featured"], "also_publish" => "1"
        )
      ).to eq("field" => "active", "card_fields" => [],
              "also_fields" => ["featured"], "also_publish" => true)
    end

    it "trims, de-dupes and omits blank labels" do
      expect(
        described_class.normalize_build_config(
          "field" => " active ", "off_label" => "  ", "on_label" => "On the menu",
          "card_fields" => [" day ", "day", ""]
        )
      ).to eq("field" => "active", "on_label" => "On the menu", "card_fields" => ["day"])
    end
  end
end
