# frozen_string_literal: true

require "rails_helper"

# The field DSL's rules, on their own (they need no records).
RSpec.describe BlockType::Validator do
  it "validate fields definition rejects bad name" do
    fields = [{"name" => "Bad Name", "type" => "string"}]
    errs = BlockType::Validator.validate_fields_definition(fields)
    expect(errs.join).to include("lowercase snake_case")
  end

  it "validate data requires field" do
    fields = [{"name" => "title", "type" => "string", "required" => true}]
    errs = BlockType::Validator.validate_data(fields, {})
    expect(errs["title"]).to eq(["is required"])
  end

  it "json schema for generates basic schema" do
    fields = [{"name" => "count", "type" => "integer"}]
    schema = BlockType::Validator.json_schema_for(fields)
    expect(schema["properties"]["count"]["type"]).to eq("integer")
  end

  # `code` is a raw-text field type (rendered as a plain monospace textarea in
  # the editor) for unsanitized HTML / <script> snippets / JSON config.
  it "code is a valid field type" do
    fields = [{"name" => "head", "type" => "code"}]
    expect(BlockType::Validator.validate_fields_definition(fields)).to be_empty
  end

  it "validate data code must be a string" do
    fields = [{"name" => "head", "type" => "code"}]
    expect(BlockType::Validator.validate_data(fields, {"head" => "<script>x()</script>"})).to be_empty
    errs = BlockType::Validator.validate_data(fields, {"head" => 123})
    expect(errs["head"]).to eq(["must be a string"])
  end

  it "coerce data code stringifies" do
    fields = [{"name" => "head", "type" => "code"}]
    expect(BlockType::Validator.coerce_data(fields, {"head" => 42})["head"]).to eq("42")
  end

  it "json schema for code is string" do
    fields = [{"name" => "head", "type" => "code"}]
    schema = BlockType::Validator.json_schema_for(fields)
    expect(schema["properties"]["head"]["type"]).to eq("string")
  end

  # ── group: a single nested object (like a repeater without the array) ──

  let(:group_fields) do
    [{
    "name" => "button", "type" => "group",
    "of" => [
      {"name" => "label", "type" => "string", "required" => true},
      {"name" => "link",  "type" => "url"}
    ]
  }]
  end

  it "group is a valid field type" do
    expect(BlockType::Validator.validate_fields_definition(group_fields)).to be_empty
  end

  it "group definition requires an of array" do
    fields = [{"name" => "button", "type" => "group"}]
    expect(BlockType::Validator.validate_fields_definition(fields).join).to include("needs an 'of' array")
  end

  it "group validates nested sub fields" do
    ok = BlockType::Validator.validate_data(group_fields, {"button" => {"label" => "Book", "link" => "https://x.com"}})
    expect(ok).to be_empty
  end

  it "group value must be an object" do
    errs = BlockType::Validator.validate_data(group_fields, {"button" => ["not", "a", "hash"]})
    expect(errs["button"]).to eq(["must be an object"])
  end

  it "group surfaces nested required errors" do
    errs = BlockType::Validator.validate_data(group_fields, {"button" => {"link" => "https://x.com"}})
    expect(errs["button.label"]).to eq(["is required"])
  end

  it "group coerces nested sub fields" do
    coerced = BlockType::Validator.coerce_data(group_fields, {"button" => {"label" => 42}})
    expect(coerced["button"]["label"]).to eq("42")
  end

  it "group extracts nested references" do
    fields = [{"name" => "hero", "type" => "group", "of" => [{"name" => "img", "type" => "asset"}]}]
    refs = []
    BlockType::Validator.each_reference_in(fields, {"hero" => {"img" => "abc123"}}) { |*a| refs << a }
    expect(refs).to include([:asset, "asset", "abc123"])
  end

  it "json schema for group is object" do
    schema = BlockType::Validator.json_schema_for(group_fields)
    expect(schema["properties"]["button"]["type"]).to eq("object")
    expect(schema["properties"]["button"]["properties"]["label"]["type"]).to eq("string")
  end
end
