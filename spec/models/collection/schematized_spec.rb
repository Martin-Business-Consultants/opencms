# frozen_string_literal: true

require "rails_helper"

RSpec.describe Collection::Schematized do
  let(:collection) do
    Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => [
      {"name" => "featured", "type" => "boolean"}, {"name" => "summary", "type" => "string"}
    ]})
  end

  it "finds its fields and its yes/no fields by name" do
    expect(collection.field("summary")).to include("type" => "string")
    expect(collection.field("")).to be_nil
    expect(collection.boolean_fields.map { it["name"] }).to eq(%w[featured])
    expect(collection.boolean_field("summary")).to be_nil
  end

  it "changes its schema and records it" do
    expect(collection.change_schema(schema: {"fields" => [{"name" => "answer", "type" => "text"}]})).to be(true)

    expect(collection.reload.fields.map { it["name"] }).to eq(%w[answer])
    expect(AuditLog.last).to have_attributes(action: "collection.schema_updated", metadata: {"slug" => "posts"})
  end

  it "records nothing when the schema doesn't save" do
    expect { expect(collection.change_schema(schema: {"fields" => [{"name" => "x", "type" => "nonsense"}]})).to be(false) }
      .not_to change(AuditLog, :count)
    expect { collection.change_schema!(schema: {"fields" => [{"name" => "x", "type" => "nonsense"}]}) }
      .to raise_error(ActiveRecord::RecordInvalid)
  end
end
