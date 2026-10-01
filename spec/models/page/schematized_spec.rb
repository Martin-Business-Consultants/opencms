# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::Schematized do
  let(:page) { Page.create!(slug: "about", title: "About", status: "draft", locale: "en") }
  let(:fields) { [{"name" => "note", "type" => "string", "label" => "Note"}] }

  it "replaces the field definitions and records it" do
    expect(page.update_schema(fields)).to be(true)

    expect(page.reload.fields).to eq(fields)
    expect(AuditLog.last).to have_attributes(action: "page.schema_updated", metadata: {"path" => "about"})
  end

  it "records nothing when the schema is refused" do
    expect { expect(page.update_schema([{"name" => "x", "type" => "nonsense"}])).to be(false) }
      .not_to change(AuditLog, :count)
    expect { page.update_schema!([{"name" => "x", "type" => "nonsense"}]) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
