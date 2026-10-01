# frozen_string_literal: true

require "rails_helper"

RSpec.describe Collection::Iconic do
  it "keeps the template's lucide icon and draws it with the admin's icons" do
    template = Collection::TEMPLATES.find { it["icon"] == "Calendar" }
    collection = Collection.new
    collection.apply_template(template)

    expect(collection.icon).to eq("Calendar")
    expect(collection.admin_icon).to eq("calendar")
  end

  it "draws the stack for no icon or one the admin can't draw" do
    expect(Collection.new.admin_icon).to eq("stack")
    expect(Collection.new(icon: "Rocket").admin_icon).to eq("stack")
  end

  it "maps every template's icon onto the admin's icon set" do
    Collection::TEMPLATES.each do |template|
      expect(Collection::Iconic::ADMIN_ICONS).to have_key(template["icon"]), "#{template["key"]}: #{template["icon"]}"
    end
  end
end
