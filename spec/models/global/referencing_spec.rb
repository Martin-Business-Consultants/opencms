# frozen_string_literal: true

require "rails_helper"

RSpec.describe Global::Referencing do
  it "keeps the assets its data points at as content references" do
    global = Global.create!(slug: "footer", name: "Footer",
      schema: {"fields" => [{"name" => "logo_id", "type" => "asset"}]}, data: {"logo_id" => "42"})

    expect(global.content_references.pluck(:ref_type, :ref_id, :kind)).to eq([%w[asset 42 asset]])

    global.update!(data: {})
    expect(global.content_references.reload).to be_empty
  end
end
