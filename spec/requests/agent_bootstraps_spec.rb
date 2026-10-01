# frozen_string_literal: true

require "rails_helper"
require "tempfile"

RSpec.describe "Agent bootstrap", type: :request do
  before do
    SiteSetup.new(name: "Agent Bootstrap Spec", owner_email: "owner@example.com").call
    host! "agentboot.librepublish.com"
  end

  it "serves the installer without a session — `curl | sh` can't sign in" do
    get "/agent/install.sh"

    expect(response).to have_http_status(:success)
    expect(response.body).to start_with("#!/bin/sh")
  end

  it "bakes this install's URL and site key into what it serves" do
    get "/agent/install.sh"

    expect(response.body).to include("agentboot.librepublish.com")
    expect(response.body).to include(%(SITE="#{Site.key}"))
    expect(response.body).not_to include("__CMS_URL__")
    expect(response.body).not_to include("__SITE__")
  end

  it "hands out an https URL to a remote caller, whatever scheme the proxy used" do
    # TLS is terminated upstream, so the app itself sees plain http — but a
    # token gets pasted into this URL, so it must not go out over http.
    get "/agent/install.sh", headers: {"REMOTE_ADDR" => "203.0.113.5"}

    expect(response.body).to include("https://agentboot.librepublish.com")
    expect(response.body).not_to include("http://agentboot.librepublish.com")
  end

  it "serves the CLI the installer downloads" do
    get "/agent/cms"

    expect(response).to have_http_status(:success)
    expect(response.body).to start_with("#!/usr/bin/env ruby")
    expect(response.body).to include("api_tokens/me")
  end

  # An agent's first move on an unfamiliar machine is to ask the CLI what it can
  # do. If that catalogue is missing, everything downstream is guesswork.
  it "serves a CLI that can describe its own surface" do
    get "/agent/cms"

    expect(response.body).to include("cms commands --json")
    expect(response.body).to include("X-Agent-Envelope")
  end

  # The installer downloads and runs the CLI, so a syntax error here is a broken
  # install on someone else's machine rather than a red build on ours.
  it "serves a CLI that parses" do
    get "/agent/cms"

    file = Tempfile.new(["cms", ".rb"])
    file.write(response.body)
    file.close

    expect(system("ruby", "-c", file.path, out: File::NULL, err: File::NULL))
      .to be(true), "the served CLI is not valid Ruby"
  ensure
    file&.unlink
  end

  it "serves an AGENTS.md that asks for the site repo and can be recognised again" do
    get "/agent/AGENTS.md"

    expect(response).to have_http_status(:success)
    # The installer greps for this marker to avoid appending itself twice.
    expect(response.body).to include("librepublish:cms-agent")
    expect(response.body).to include("gh repo clone")
    expect(response.body).to match(/ask the user which Astro repo/i)
  end

  it "serves the Claude Code skill with usable frontmatter" do
    get "/agent/SKILL.md"

    expect(response).to have_http_status(:success)
    expect(response.body).to start_with("---")
    expect(response.body).to include("name: cms")
  end

  it "hands out no secrets — the operator supplies the token" do
    %w[/agent/install.sh /agent/cms /agent/AGENTS.md /agent/SKILL.md].each do |path|
      get path
      expect(response.body).not_to match(/mbc_[A-Za-z0-9_-]{20,}/)
    end
  end
end
