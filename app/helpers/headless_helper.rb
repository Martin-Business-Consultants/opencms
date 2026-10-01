# frozen_string_literal: true

# What makes the CMS's headlessness visible in the admin: the JSON tab's
# client call, and the Developers screen's pieces.
module HeadlessHelper
  # The integration's client call (integrations/astro/cms.ts) that fetches
  # the record at an API path.
  def api_json_client_call(path)
    path = path.split("?").first
    case path
    when %r{\A/api/pages/(.+)\z} then %(const page = await cms.pages.get(#{$1.to_json});)
    when %r{\A/api/collections/([^/]+)/entries/([^/]+)\z} then %(const entry = await cms.collections.entry(#{$1.to_json}, #{$2.to_json});)
    when %r{\A/api/globals/([^/]+)\z} then %(const global = await cms.globals.get(#{$1.to_json});)
    end
  end

  # The `cms` command (and MCP tool) that returns the record at an API path.
  def api_json_cli_call(path)
    case path.split("?").first
    when %r{\A/api/pages/(.+)\z} then "cms page #{$1}"
    when %r{\A/api/collections/([^/]+)/entries/([^/]+)\z} then "cms entry #{$1} #{$2}"
    when %r{\A/api/globals/([^/]+)\z} then "cms global #{$1}"
    end
  end

  # The `cms` command that does what this admin screen shows, for the line
  # under its title (layouts/shared/page_header): the admin is for doing
  # things by hand, and the CLI (and MCP, and the API under both) is the
  # real surface. Nil for a screen with no one command.
  def cli_command_hint
    case [controller_path, action_name]
    in ["dashboard", "index"] then "cms doctor"
    in ["pages", "index"] then "cms pages"
    in ["pages", "edit"] if @page then "cms page #{@page.path}"
    in ["pages/schemas", "show"] if @page then "cms schema page #{@page.path} < fields.json"
    in ["sitemaps", "index"] then "cms sitemap"
    in ["collections", "index"] then "cms collections"
    in ["collections/schemas", "show"] if @collection then "cms collection #{@collection.slug}"
    in ["collection_entries", "index"] if @collection then "cms entries #{@collection.slug}"
    in ["collection_entries", "edit"] if @collection && @entry then "cms entry #{@collection.slug} #{@entry.slug}"
    in ["globals", "index"] then "cms globals"
    in ["globals", "edit"] if @global then "cms global #{@global.slug}"
    in ["block_types", "index"] then "cms blocks"
    in ["file_manager", "index"] then "cms assets"
    in ["file_manager/assets", "show"] if @asset then "cms asset #{@asset.id}"
    in ["forms", "index"] then "cms forms"
    in ["form_emails", "edit"] if @form && @email then "cms email #{@form.slug} #{@email.kind}"
    in ["submissions", "index"] then "cms submissions"
    in ["approvals" | "review_requests", "index"] then "cms reviews"
    in ["recommendations", "index" | "show"] then "cms findings"
    in ["audit_logs", "index"] then "cms audit"
    in ["trash", "index"] then "cms trash"
    in ["tools/redirects", "index"] then "cms redirects"
    in ["tools/recurring_tasks", "index"] then "cms schedules"
    in ["tools/backups", "show"] then "cms backup > backup.tar.gz"
    in ["webhooks", "index"] then "cms webhooks"
    in ["settings/deploys", "show"] then "cms deploy"
    in ["settings/updates", "show"] then "cms updates"
    in ["settings/service_tokens", "index"] then "cms service-tokens"
    in ["settings/api_tokens", "show"] then "cms whoami"
    in ["settings/brands", "show"] then "cms brand"
    in ["developers", "show"] then "cms frontend"
    in ["docs", "index"] then "cms docs"
    in ["docs", "show"] if @guide then "cms docs #{@guide.slug}"
    in ["docs", "go_live"] then "cms go-live"
    in ["docs", "site_health"] then "cms site-health"
    else nil
    end
  end
end
