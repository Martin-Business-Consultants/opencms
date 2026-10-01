# frozen_string_literal: true

require "rails_helper"

RSpec.describe Collection::Templated do
  it "starts a collection from a template, keeping a name and slug already chosen" do
    collection = Collection.new(name: "Our FAQ", slug: "")

    collection.apply_template(Collection.template("faq"))

    expect(collection).to have_attributes(name: "Our FAQ", slug: "faqs")
    expect(collection.fields).to eq(Collection.template("faq")["fields"])
  end

  it "has no template for an unknown key" do
    expect(Collection.template("nope")).to be_nil
  end

  it "records its creation with the template it came from" do
    collection = Collection.create!(slug: "faqs", name: "FAQs", schema: {"fields" => []})

    collection.track_creation(template: "faq")

    expect(AuditLog.last).to have_attributes(action: "collection.created", target: collection,
      metadata: {"slug" => "faqs", "template" => "faq"})
  end
end
