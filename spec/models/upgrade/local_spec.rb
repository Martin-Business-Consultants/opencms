# frozen_string_literal: true

require "rails_helper"

RSpec.describe Upgrade::Local do
  let(:data_dir) { Pathname(Dir.mktmpdir("cms-data")) }
  let(:upgrade) { Upgrade.create!(requested_by: create(:user), from_version: Cms::VERSION, to_version: "99.0.0", via: "local") }
  let(:directory) { data_dir.join("updates", upgrade.id.to_s) }

  around { |example| with_env("CMS_DATA_DIR" => data_dir.to_s) { example.run } }
  after { data_dir.rmtree }

  it "runs bin/update with the tag in its own process group, writing to the data directory" do
    expect(Process).to receive(:spawn) do |*args, **options|
      expect(args).to include("bin/update \"$1\" > \"$2\" 2>&1; echo $? > \"$3\"", "v99.0.0",
        directory.join("update.log").to_s, directory.join("exit_status").to_s)
      expect(options).to include(chdir: Rails.root.to_s, pgroup: true)
      4242
    end
    expect(Process).to receive(:detach).with(4242)

    described_class.new(upgrade).start

    expect(directory).to be_directory
  end

  it "leaves the update running while bin/update hasn't finished, or finished well" do
    described_class.new(upgrade).check
    expect(upgrade.reload).to be_running

    directory.mkpath
    directory.join("exit_status").write("0\n")
    described_class.new(upgrade).check
    expect(upgrade.reload).to be_running
  end

  it "fails the update with the end of bin/update's output when it stopped" do
    directory.mkpath
    directory.join("update.log").write((1..30).map { "line #{it}\n" }.join + "migration failed\n")
    directory.join("exit_status").write("1\n")

    described_class.new(upgrade).check

    expect(upgrade.reload).to be_failed
    expect(upgrade.message).to start_with("bin/update stopped (exit 1):\n").and end_with("migration failed\n")
    expect(upgrade.message).not_to include("line 11\n")
  end

  it "says where its output is" do
    expect(described_class.new(upgrade).where_to_look).to eq("Its output is in #{directory.join("update.log")}.")
  end
end
