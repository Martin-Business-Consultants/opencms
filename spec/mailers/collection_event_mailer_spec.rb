# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEventMailer do
  let(:collection) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }
  let(:entry) { collection.entries.create!(slug: "hello", title: "Hello", status: "draft", locale: "en") }

  def sent
    described_class.with(collection: collection, entry: entry, event: "created", payload: {}, recipients: ["ed@acme.test"]).event
  end

  it "sends from the core's sender in Settings › General" do
    Setting.set("general", {"email_from_name" => "Acme", "email_from_address" => "news@acme.test"})
    Setting.set("forms_settings", {"from_name" => "Forms", "from_email" => "forms@acme.test"})

    expect(sent[:from].value).to eq(%("Acme" <news@acme.test>))
  end

  it "falls back to the Forms plugin's sender, as it used before, then the default" do
    Setting.set("forms_settings", {"from_name" => "Forms", "from_email" => "forms@acme.test"})
    expect(sent[:from].value).to eq(%("Forms" <forms@acme.test>))

    Setting.delete_key("forms_settings")
    expect(sent.from).to eq([described_class.default_from_email])
  end
end
