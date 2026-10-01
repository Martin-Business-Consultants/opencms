# frozen_string_literal: true

require "rails_helper"

# db:prepare on an empty data directory seeds: a fresh install must get the
# site's starter content and no demo accounts or pages.
RSpec.describe "db/seeds.rb" do
  it "gives a non-development install its starter content only" do
    load Rails.root.join("db/seeds.rb")

    expect(User.count).to eq(0)
    expect(Role.find_by(name: "Editor")).to be_present
    expect(BlockType.count).to be_positive
    expect(Page.where(title: "Kalamazoo Mortgage")).to be_empty
  end
end
