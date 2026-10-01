# frozen_string_literal: true

require "rails_helper"
require "rubygems/package"
require "zlib"

RSpec.describe SiteBackup do
  # `dump_to` closes the underlying IO via Zlib::GzipWriter.wrap, so read the
  # captured bytes back through a fresh reader.
  def entries_of(backup)
    io = StringIO.new
    backup.dump_to(io)

    entries = {}
    Zlib::GzipReader.wrap(StringIO.new(io.string)) do |gz|
      Gem::Package::TarReader.new(gz) do |tar|
        tar.each { |entry| entries[entry.full_name] = entry.read }
      end
    end
    entries
  end

  it "produces a tar.gz with the manifest and the database" do
    entries = entries_of(described_class.new)

    expect(entries.keys).to include("manifest.json", "db/main.sqlite3")
    expect(JSON.parse(entries["manifest.json"])["tenant"]).to eq(Site.key)
  end

  it "includes every uploaded file an asset holds" do
    asset = Asset.new(folder: "/")
    asset.file.attach(io: StringIO.new("PNG-BYTES"), filename: "logo.png", content_type: "image/png")
    asset.save!

    entries = entries_of(described_class.new)

    expect(entries["blobs/#{asset.file.blob.key}"]).to eq("PNG-BYTES")
  end

  it "uses an informative filename" do
    expect(described_class.new.filename).to match(/\Acms-backup-#{Regexp.escape(Site.key)}-\d{8}-\d{6}\.tar\.gz\z/)
  end
end
