# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::Referencing do
  it "records what the page links to, rewritten on every save" do
    page = Page.create!(slug: "about", title: "About", status: "draft", locale: "en",
      schema: {"fields" => [{"name" => "more", "type" => "link", "label" => "More"}]},
      frontmatter: {"more" => {"kind" => "page", "value" => "team"}})

    expect(page.content_references.pluck(:ref_type, :ref_id, :position)).to eq([["page", "team", -1]])

    page.update!(frontmatter: {"more" => {"kind" => "page", "value" => "jobs"}})

    expect(page.content_references.reload.pluck(:ref_id)).to eq(%w[jobs])
  end
end
