# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preview do
  it "keeps a draft under a token the Astro site can read back" do
    issued = described_class.issue(page_id: 7)
    described_class.write(issued[:token], {title: "Draft"})

    expect(described_class.page_id_for(issued[:token])).to eq(7)
    expect(described_class.read(issued[:token])).to eq(title: "Draft")
    expect(described_class.verify("garbage")).to be_nil
  end

  it "points at the site's /_preview/<path> when it has a base URL" do
    Setting.set("general", site_base_url: "https://www.site.test/")
    expect(described_class.public_url("about", "tok")).to eq("https://www.site.test/_preview/about?preview=tok")

    Setting.set("general", site_base_url: "")
    expect(described_class.public_url("about", "tok")).to be_nil
  end
end
