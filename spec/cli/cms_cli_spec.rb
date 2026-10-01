# frozen_string_literal: true

require "json"
require "tmpdir"
require "open3"

# The `cms` CLI is a single stdlib-only Ruby file, so it can be exercised as
# itself rather than through Rails. What is worth pinning here is the part an
# agent depends on and a person never looks at: the catalogue. It is the one
# description of the surface, and the dispatcher runs from the same table, so a
# command missing its usage or notes is a command an agent will misuse.
RSpec.describe "cms CLI" do
  CLI = File.expand_path("../../agent/cms", __dir__)

  # No credentials in the environment, so a command that tries to reach a server
  # fails predictably instead of picking up the developer's own profile.
  def run(*args)
    stdout, stderr, status = Open3.capture3(
      {"CMS_URL" => "", "USER_AGENT_TOKEN" => "", "CMS_TOKEN" => "", "CMS_PROFILE" => "",
       "XDG_CONFIG_HOME" => Dir.mktmpdir},
      "ruby", CLI, *args
    )
    [stdout, stderr, status.exitstatus]
  end

  def catalogue
    stdout, = run("commands", "--json")
    JSON.parse(stdout).fetch("data")
  end

  it "describes its whole surface in one call" do
    data = catalogue

    expect(data["commands"].size).to be > 50
    expect(data["global_flags"].map { |f| f["flag"] }).to include("--agent", "--profile NAME")
  end

  it "gives every command a name, a summary and a usage line" do
    catalogue["commands"].each do |command|
      expect(command["name"]).not_to be_empty
      expect(command["summary"].to_s).not_to be_empty, "#{command["name"]} has no summary"
      expect(command["usage"]).to start_with("cms "), "#{command["name"]} has no usage line"
    end
  end

  # The catalogue and the dispatcher read the same table, so this is really
  # asserting that nothing in it is unreachable.
  it "answers --help for every command it lists" do
    catalogue["commands"].each do |command|
      stdout, _stderr, status = run(command["name"], "--help")
      expect(status).to eq(0), "cms #{command["name"]} --help exited #{status}"
      expect(stdout).to include(command["usage"])
    end
  end

  it "covers the whole run loop" do
    names = catalogue["commands"].map { |c| c["name"] }

    expect(names).to include("work", "run-start", "run-ping", "run-step", "run-done", "run-fail")
    expect(names).to include("recommend", "findings")
  end

  it "keeps an escape hatch for anything the curated commands miss" do
    names = catalogue["commands"].map { |c| c["name"] }

    expect(names).to include("get", "post", "patch", "delete")
  end

  describe "without credentials" do
    it "says how to get them rather than failing obscurely" do
      _stdout, stderr, status = run("pages")

      expect(status).to eq(1)
      expect(stderr).to include("cms login")
    end

    it "names the profile that is missing, when one was asked for" do
      _stdout, stderr, = run("--profile", "acme", "pages")

      expect(stderr).to include("no profile named 'acme'")
      expect(stderr).to include("--profile acme")
    end

    # `cms login` is what creates a profile, so it must not be blocked by that
    # profile not existing yet.
    it "still lets login run for a profile that does not exist yet" do
      _stdout, stderr, = run("login", "--profile", "acme")

      expect(stderr).not_to include("no profile named")
    end
  end

  it "refuses an unknown command with a pointer to the catalogue" do
    _stdout, stderr, status = run("frobnicate")

    expect(status).to eq(1)
    expect(stderr).to include("cms commands")
  end

  it "prints a usage screen grouped by what things are for" do
    stdout, = run("help")

    expect(stdout).to include("Agent work", "Content", "Publishing")
    expect(stdout).to include("cms doctor")
  end
end
