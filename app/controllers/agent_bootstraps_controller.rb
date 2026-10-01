# frozen_string_literal: true

# Serves the local-agent bootstrap: a one-liner a person runs on their own
# machine to point Claude Code / opencode / Codex at this site.
#
#   curl -fsSL https://<host>/agent/install.sh | sh
#
# The installer then pulls the other three files from here — the `cms` CLI, the
# AGENTS.md written into the working directory, and the Claude Code skill. All
# four live in `agent/` in the repo, so they're reviewed and versioned like
# code rather than pasted onto machines.
#
# Deliberately unauthenticated. Everything served is public documentation and
# a shell script — no site content, no secrets. The token is never handed out
# here: the installer asks the operator for it and verifies it against
# `/api/api_tokens/me`. Requiring a session would break `curl | sh`, which is
# the whole point of the endpoint.
#
# `__CMS_URL__` and `__SITE__` are interpolated per request so a downloaded
# script already knows which workspace it belongs to.
class AgentBootstrapsController < ApplicationController
  skip_authorization
  skip_before_action :authenticate, raise: false

  FILES = {
    install:   {path: "install.sh",           type: "text/x-shellscript"},
    cli:       {path: "cms",                  type: "text/x-ruby"},
    agents_md: {path: "AGENTS.md",            type: "text/markdown"},
    skill:     {path: "skills/cms/SKILL.md",  type: "text/markdown"},
    # Not the installer's: the site repo's AGENTS.md, written by the Astro
    # integration (integrations/astro) so an agent there knows how the site
    # works with this CMS.
    frontend_md: {path: "FRONTEND.md",        type: "text/markdown"},
    # The Astro installer: run in a site's project, it fetches FRONTEND_FILES,
    # wires cms() into astro.config and gets the site a token.
    frontend_install: {path: "frontend-install.sh", type: "text/x-shellscript"}
  }.freeze

  # What the Astro installer downloads into a site, from integrations/astro.
  # The email route's imports are made relative, as a site may have no `~`
  # alias; everything else is served as it is in the repo.
  FRONTEND_FILES = %w[cms.ts types.ts blocks.ts sitemap.ts emails.ts integration.ts webhook-handler.ts]
    .to_h { [it, it] }.merge("email-route.astro" => "examples/emails/[form]/[kind].astro").freeze
  INTEGRATION_ROOT = Rails.root.join("integrations/astro")

  ROOT = Rails.root.join("agent")

  FILES.each_key do |name|
    define_method(name) { serve(name) }
  end

  # GET /frontend/files/:name — one of the integration's files.
  def frontend_file
    source = FRONTEND_FILES[params[:name].to_s] or raise ActionController::RoutingError, "unknown file"
    body = INTEGRATION_ROOT.join(source).read
    body = body.gsub('"~/lib/cms/', '"../../../lib/cms/') if params[:name] == "email-route.astro"

    render plain: body, content_type: "text/plain"
  end

  private

  def serve(name)
    file = FILES.fetch(name)
    body = ROOT.join(file[:path]).read

    render plain: interpolate(body), content_type: file[:type]
  end

  def interpolate(body)
    body
      .gsub("__CMS_URL__", cms_url)
      .gsub("__SITE__", Site.key.presence || "this workspace")
  end

  # An API token gets pasted into whatever URL we bake in here, so never hand
  # out an `http://` one for a real host: TLS is usually terminated at a proxy
  # and the app sees plain http even when the caller arrived over https. Local
  # development, where there is no TLS to speak of, keeps the scheme it has.
  def cms_url
    url = request.base_url
    return url if request.local? || url.start_with?("https://")

    url.sub(/\Ahttp:/, "https:")
  end
end
