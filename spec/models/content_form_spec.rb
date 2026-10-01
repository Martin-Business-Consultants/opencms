# frozen_string_literal: true

require "rails_helper"

# ContentForm's rules for reading a content form back without disturbing
# what nobody edited.
RSpec.describe ContentForm do
  let(:fields) do
    [
      {"name" => "title", "type" => "string"},
      {"name" => "count", "type" => "integer"},
      {"name" => "shown", "type" => "boolean"},
      {"name" => "cta", "type" => "link"},
      {"name" => "items", "type" => "repeater", "of" => [{"name" => "label", "type" => "string"}]}
    ]
  end

  def decode(submitted, original)
    described_class.object(fields, submitted, original: original, block_types: {})
  end

  it "keeps the stored key order, extra keys and value types when an edit touches one field" do
    original = {"extra" => {"x" => 1}, "count" => "3", "title" => "Old"}
    decoded = decode({"title" => "New", "count" => "3", "shown" => "0"}, original)

    expect(decoded.to_json).to eq({"extra" => {"x" => 1}, "count" => "3", "title" => "New"}.to_json)
  end

  it "leaves a field the object never had absent when nothing was entered" do
    expect(decode({"title" => "", "shown" => "0", "count" => "", "items" => {"_list" => "1"}}, {})).to eq({})
  end

  it "writes what was entered, cast to the field's type" do
    decoded = decode({"count" => "12", "shown" => "1", "cta" => {"kind" => "entry", "url" => "", "page" => "", "entry" => "posts/hello"}}, {})

    expect(decoded).to eq("count" => 12, "shown" => true, "cta" => {"kind" => "entry", "collection" => "posts", "value" => "hello"})
  end

  it "reads repeater items in posted order, each against the item it was rendered from" do
    original = {"items" => [{"label" => "A", "note" => "keep"}, {"label" => "B"}]}
    submitted = {"items" => {
      "_list" => "1",
      "r2" => {"_original" => {"label" => "B"}.to_json, "label" => "B"},
      "r1" => {"_original" => {"label" => "A", "note" => "keep"}.to_json, "label" => "A"}
    }}

    expect(decode(submitted, original)["items"]).to eq([{"label" => "B"}, {"label" => "A", "note" => "keep"}])
  end

  it "keeps a field the form didn't post" do
    expect(decode({}, {"title" => "Kept"})).to eq("title" => "Kept")
  end

  it "passes a block of an unknown type through untouched" do
    block = {"id" => "x", "type" => "gone", "data" => {"a" => 1}}
    rows = {"_list" => "1", "r1" => {"_original" => block.to_json, "_json" => block.to_json}}

    expect(described_class.blocks(rows, block_types: {})).to eq([block])
  end

  it "raises on JSON that doesn't parse, naming the field" do
    json_fields = [{"name" => "json_ld", "type" => "json"}]
    expect {
      described_class.object(json_fields, {"json_ld" => "{nope"}, original: {}, block_types: {}, path: "seo")
    }.to raise_error(ContentForm::InvalidJson, /seo\.json_ld is not valid JSON/)
  end
end
