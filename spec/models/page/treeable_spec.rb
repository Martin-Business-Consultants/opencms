# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::Treeable do
  def make(slug, parent: nil) = Page.create!(slug: slug, title: slug.titleize, status: "draft", locale: "en", parent: parent)

  it "derives path and depth from the parent" do
    team = make("team", parent: make("about"))

    expect(team).to have_attributes(path: "about/team", depth: 1, to_param: "about/team")
  end

  it "rewrites descendants' paths when a page moves or is renamed" do
    about = make("about")
    team = make("team", parent: about)
    alice = make("alice", parent: team)

    about.update!(slug: "company")

    expect([team.reload.path, alice.reload.path]).to eq(%w[company/team company/team/alice])
    expect(alice.depth).to eq(2)
  end

  it "refuses a parent that would make a cycle" do
    about = make("about")
    team = make("team", parent: about)

    about.parent = team

    expect(about).not_to be_valid
    expect(about.errors[:parent_id]).to be_present
  end

  it "lists ancestors oldest first and descendants breadth first" do
    about = make("about")
    team = make("team", parent: about)
    alice = make("alice", parent: team)

    expect(alice.ancestors).to eq([about, team])
    expect(about.descendants).to eq([team, alice])
  end

  it "trashes children with their parent" do
    about = make("about")
    team = make("team", parent: about)

    about.discard!

    expect(Page.with_discarded.find(team.id)).to be_discarded
  end
end
