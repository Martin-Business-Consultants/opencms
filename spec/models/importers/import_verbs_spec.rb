# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Importer adapters' import verbs" do
  include ActiveJob::TestHelper

  it "queues each adapter's own job" do
    expect { Importers::Adapters::Wordpress.import_later("/tmp/x.xml", "/tmp/x") }
      .to have_enqueued_job(Importers::WordpressJob).with("/tmp/x.xml", "/tmp/x")
    expect { Importers::Adapters::Directus.import_later("/tmp/x.db", "/tmp/x") }
      .to have_enqueued_job(Importers::DirectusJob).with("/tmp/x.db", "/tmp/x")
    options = {repo_url: "https://github.com/acme/site", ref: "main", content_path: "src/content",
               pages_path: "src/pages", assets_path: "src/assets", rewrite_images: true}
    expect { Importers::Adapters::Astro.import_later(**options) }.to have_enqueued_job(Importers::AstroJob).with(**options)
  end

  it "imports an Astro repo it has fetched, and cleans up" do
    repo = Pathname(Dir.mktmpdir("astro-fixture"))
    (repo / "src/content/posts").mkpath
    (repo / "src/content/posts/hello.md").write("---\ntitle: Hello\n---\n\nFirst post.\n")
    allow_any_instance_of(Astro::Fetcher).to receive(:fetch).and_return(repo.to_s)

    result = Importers::Adapters::Astro.import_now(repo_url: "https://github.com/acme/site", ref: "main",
      content_path: "src/content", pages_path: "", assets_path: "", rewrite_images: true)

    expect(result.entries_created).to eq(1)
    expect(CollectionEntry.find_by(slug: "hello").title).to eq("Hello")
  ensure
    FileUtils.rm_rf(repo) if repo
  end
end
