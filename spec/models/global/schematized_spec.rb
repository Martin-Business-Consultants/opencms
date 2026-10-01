# frozen_string_literal: true

require "rails_helper"

RSpec.describe Global::Schematized do
  let(:global) { Global.create!(slug: "footer", name: "Footer", schema: {"fields" => [{"name" => "tagline", "type" => "string"}]}, data: {"tagline" => "Hi"}) }

  it "reads its fields from the schema" do
    expect(global.fields.map { it["name"] }).to eq(%w[tagline])
    expect(global.frontmatter_json_schema.dig("properties", "tagline", "type")).to eq("string")
  end

  it "replaces the field list and records it" do
    expect(global.update_schema([{"name" => "phone", "type" => "string"}])).to be(true)

    expect(global.reload.fields).to eq([{"name" => "phone", "type" => "string"}])
    expect(AuditLog.last).to have_attributes(action: "global.schema_updated", target: global, metadata: {"slug" => "footer"})
  end

  it "refuses a blocks field, which only pages compose from" do
    expect(global.update_schema([{"name" => "body", "type" => "blocks"}])).to be(false)
    expect(global.errors[:schema]).to be_present
    expect { global.update_schema!([{"name" => "body", "type" => "blocks"}]) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "validates its data against the fields" do
    global = Global.new(slug: "nav", name: "Nav", schema: {"fields" => [{"name" => "count", "type" => "integer"}]}, data: {"count" => "abc"})

    expect(global).not_to be_valid
    expect(global.errors[:data].join).to include("count")
  end
end
