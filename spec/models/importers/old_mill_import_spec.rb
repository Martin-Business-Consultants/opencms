# frozen_string_literal: true

require "rails_helper"

RSpec.describe Importers::OldMillImport do
  let(:dir) { Dir.mktmpdir("wp-import") }
  let(:xml) { write_wordpress_export(dir) }
  let(:dest) { File.join(dir, "out") }
  let(:quiet) { StringIO.new }

  before do
    BlockType.seed
    stub_wordpress_downloads
  end

  after { FileUtils.rm_rf(dir) }

  def run(stage = :all, **options)
    described_class.new(xml, dest, out: quiet, err: quiet, **options).public_send(stage)
  end

  it "imports media, the general global, beers, food, specials and pages, offline" do
    run

    hops = Asset.find_by(name: "Hop field")
    expect(hops.file.download).to eq(ImporterFixtures::PNG)
    expect(Global.find_by(slug: "general").data["city"]).to eq("Plainwell")

    beer = Collection.find_by(slug: "beers").entries.find_by(slug: "mill-pond-ipa")
    expect(beer).to have_attributes(status: "published", body_markdown: "Bright & **bitter**.")
    expect(beer.frontmatter).to eq("abv" => "6.4", "featured_image" => hops.id.to_s)
    expect(beer.category.slug).to eq("ipa")
    expect(beer.seo).to eq("description" => "Our flagship IPA.")

    dish = Collection.find_by(slug: "food").entries.find_by(slug: "pretzel-bites")
    expect(dish.category.slug).to eq("appetizers")
    expect(dish.category.frontmatter["position"]).to eq(10)

    special = Collection.find_by(slug: "specials").entries.sole
    expect(special.slug).to eq("pretzel-bites-special-20240306")
    expect(special.frontmatter["food_item"]).to eq("pretzel-bites")
    expect(special.body_markdown).to eq("Half off all night.")

    about = Page.find_by(slug: "about")
    expect(about.blocks.map { it["type"] }).to eq(%w[text text image])
    expect(about.blocks.last["data"]).to include("asset_id" => hops.id.to_s, "caption" => "Our hops")
    beers_page = Page.find_by(slug: "beers")
    expect(beers_page.parent).to eq(about)
    expect(beers_page.blocks.sole["type"]).to eq("collection_list")
  end

  it "re-imports to the same records" do
    run
    expect { run }.not_to change { [Asset.count, CollectionEntry.count, Page.count, Collection.count] }
  end

  it "leaves existing beers alone in create mode" do
    run
    beer = Collection.find_by(slug: "beers").entries.find_by(slug: "mill-pond-ipa")
    beer.update!(title: "Edited in the CMS")

    run(:beers, mode: "create")

    expect(beer.reload.title).to eq("Edited in the CMS")
  end

  it "says what's missing rather than exiting" do
    expect { described_class.new(File.join(dir, "nope.xml"), dest, out: quiet, err: quiet).media }
      .to raise_error(described_class::Error, /XML not found/)
    expect { described_class.new(xml, dest, out: quiet, err: quiet).assets }
      .to raise_error(described_class::Error, /Run import:wordpress:media first/)
    expect { described_class.new(xml, dest, mode: "merge") }.to raise_error(described_class::Error, /mode must be/)
  end

  it "keeps the rake stages as thin wrappers" do
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("import:wordpress:globals")
    task = Rake::Task["import:wordpress:globals"]
    task.reenable

    expect { task.invoke }.to output(/Updated Global slug=general/).to_stdout
  ensure
    task&.reenable
  end
end
