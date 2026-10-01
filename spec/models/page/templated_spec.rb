# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::Templated do
  it "offers only templates whose block types exist" do
    expect(Page.available_templates).to be_empty

    BlockType::Defaults.install!

    expect(Page.available_templates.map { it["key"] }).to include("home", "about")
  end

  it "seeds blocks, and the title and slug only when blank" do
    page = Page.new(title: "Our story")

    page.apply_template(Page.template("about"))

    expect(page).to have_attributes(title: "Our story", slug: "about", blocks: Page.template("about")["blocks"])
  end

  it "records a page made from a template" do
    page = Page.create!(slug: "about", title: "About", status: "draft", locale: "en")

    page.track_creation(template: Page.template("about"))

    expect(AuditLog.last).to have_attributes(action: "page.created",
      metadata: {"path" => "about", "status" => "draft", "template" => "about"})
  end
end
