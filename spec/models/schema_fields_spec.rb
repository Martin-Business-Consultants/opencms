# frozen_string_literal: true

require "rails_helper"

RSpec.describe SchemaFields do
  def rows(*rows)
    rows.each_with_index.to_h { |row, index| ["r#{index}", row] }
  end

  it "reads rows back in the order they were posted" do
    fields = described_class.from_params(rows(
      {"name" => "title", "label" => "Title", "type" => "string", "required" => "1"},
      {"name" => "body", "label" => "", "type" => "markdown"}
    ))

    expect(fields).to eq [
      {"name" => "title", "label" => "Title", "type" => "string", "required" => true},
      {"name" => "body", "type" => "markdown"}
    ]
  end

  it "keeps only the settings the field's type uses" do
    fields = described_class.from_params(rows(
      {"name" => "day", "type" => "string", "options" => "Monday\nTuesday", "of_collection" => "posts"}
    ))

    expect(fields.first).to eq("name" => "day", "type" => "string")
  end

  it "reads a select's choices one per line, ignoring blank lines" do
    fields = described_class.from_params(rows({"name" => "day", "type" => "select", "options" => "Monday\r\n\r\n Tuesday \n"}))

    expect(fields.first["options"]).to eq %w[Monday Tuesday]
  end

  it "nests a repeater's sub-fields" do
    fields = described_class.from_params(rows(
      {"name" => "items", "type" => "repeater", "of" => rows({"name" => "caption", "type" => "string"})}
    ))

    expect(fields.first["of"]).to eq [{"name" => "caption", "type" => "string"}]
  end

  it "puts back the keys the editor has no control for" do
    fields = described_class.from_params(rows(
      {"name" => "cta", "type" => "link", "extra" => '{"kinds":["url","page"],"name":"ignored"}'}
    ))

    expect(fields.first).to eq("kinds" => %w[url page], "name" => "cta", "type" => "link")
  end

  it "keeps a malformed show_if as text so validation names it" do
    fields = described_class.from_params(rows({"name" => "a", "type" => "string", "show_if" => "{not json"}))

    expect(fields.first["show_if"]).to eq "{not json"
  end

  it "passes JSON-style field definitions through" do
    posted = [{"name" => "a", "type" => "string", "required" => true}]

    expect(described_class.from_params(posted)).to eq posted
  end
end
