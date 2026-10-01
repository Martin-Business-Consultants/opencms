# frozen_string_literal: true

require "rails_helper"

RSpec.describe Importers::DirectusImport do
  let(:dir) { Dir.mktmpdir("directus-import") }
  let(:db) { write_directus_export(dir) }
  let(:dest) { File.join(dir, "out") }
  let(:quiet) { StringIO.new }

  after { FileUtils.rm_rf(dir) }

  def import = described_class.new(db, dest, out: quiet, err: quiet)

  it "scans, then writes collections, block types, globals and pages" do
    import.all

    posts = Collection.find_by(slug: "posts")
    expect(posts.entries.pluck(:slug, :status)).to contain_exactly(["grand-opening", "published"], [a_string_matching(/\A\S+\z/), "draft"])
    expect(BlockType.find_by(slug: "block_hero")).to be_present
    expect(Global.find_by(slug: "site_settings").data).to include("site_name" => "Old Mill")

    home = Page.find_by(slug: "home")
    expect(home.status).to eq("published")
    expect(home.blocks.sole).to include("type" => "block_hero", "data" => include("heading" => "Welcome to the mill"))

    expect(File).to exist(File.join(dest, "directus-manifest.json"))
    expect(File).to exist(File.join(dest, "directus-slug-map.json"))
  end

  it "runs a stage on its own from the sidecars an earlier one wrote" do
    import.scan
    import.collections

    expect(Collection.find_by(slug: "posts").entries.count).to eq(2)
    expect(Page.count).to eq(0)
  end

  it "says what's missing rather than exiting" do
    expect { described_class.new(nil, dest) }.to raise_error(described_class::Error, /Set db_path/)
    expect { described_class.new(File.join(dir, "none.db"), dest, out: quiet, err: quiet).scan }
      .to raise_error(described_class::Error, /DB not found/)
    expect { import.collections }.to raise_error(described_class::Error, /No manifest/)
  end
end
