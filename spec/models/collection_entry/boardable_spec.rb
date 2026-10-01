# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry::Boardable do
  let(:collection) do
    Collection.create!(slug: "specials", name: "Specials",
      schema: {"fields" => [{"name" => "active", "type" => "boolean"}, {"name" => "featured", "type" => "boolean"}, {"name" => "day", "type" => "string"}]},
      build_config: {"field" => "active", "also_fields" => ["featured"], "also_publish" => true})
  end
  let(:entry) { collection.entries.create!(slug: "tacos", title: "Tacos", status: "draft", frontmatter: {"day" => "Mon"}) }

  it "sets one field, leaving the others, and records it" do
    expect(entry.set_field("active", true)).to be(true)

    expect(entry.reload.frontmatter).to eq({"day" => "Mon", "active" => true})
    expect(AuditLog.last).to have_attributes(action: "entry.updated",
      metadata: {"collection" => "specials", "slug" => "tacos", "field" => "active", "to" => true, "status" => "draft"})
  end

  it "clears a field set to nil, unless told to keep the null" do
    entry.set_field("day", nil)
    expect(entry.reload.frontmatter).not_to have_key("day")

    entry.set_field("day", nil, keep_nil: true)
    expect(entry.reload.frontmatter).to eq({"day" => nil})
  end

  it "reads a stored string as a flag" do
    # Imports and hand-edited API writes have stored strings; the schema
    # wouldn't let one through now, so write it past validation.
    entry.update_columns(frontmatter: {"active" => "false"})

    expect(entry.flag?("active")).to be(false)
    expect(entry.board_value({"name" => "active", "type" => "boolean"})).to be(false)
  end

  it "places a card: every field the column stands for, and the status, in one save" do
    expect(entry.place_on_board(true)).to eq(%w[active featured])

    expect(entry.reload).to have_attributes(status: "published", frontmatter: {"day" => "Mon", "active" => true, "featured" => true})
    expect(AuditLog.last).to have_attributes(action: "entry.published",
      metadata: {"collection" => "specials", "slug" => "tacos", "fields" => %w[active featured], "to" => true, "from" => "draft"})
  end

  it "raises for a move that can't be saved" do
    allow(entry).to receive(:move_on_board).and_return(false)

    expect { entry.place_on_board!(true) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
