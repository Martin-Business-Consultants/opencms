# frozen_string_literal: true

module LocalMarketing
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    # The agent tools build on the Agents plugin's base class; without that
    # plugin installed there is nothing to load them into.
    initializer "local_marketing.agent_tools" do
      Rails.autoloaders.main.ignore(root.join("app/agent_tools")) unless defined?(::Agents::Engine)
    end

    # The same URLs as before it was a plugin; the custom actions became
    # resources at the same paths and route names.
    initializer "local_marketing.routes" do |app|
      app.routes.append do
        # The Marketing group's front page, its owner-facing version, and the
        # guided setup.
        get   "marketing",           to: "marketing#show",               as: :marketing
        get   "marketing/client",    to: "marketing/clients#show",       as: :marketing_client
        post  "marketing/baseline",  to: "marketing/baselines#create",   as: :marketing_baseline
        post  "marketing/hand_off",  to: "marketing/hand_offs#create",   as: :marketing_hand_off
        post  "marketing/narrative", to: "marketing/narratives#create",  as: :marketing_narrative
        get   "marketing/setup",     to: "marketing/setups#show",        as: :marketing_setup
        patch "marketing/setup",     to: "marketing/setups#update"

        # What a person has done about each citation directory, and their
        # answer to a site-audit finding — kept apart from the snapshots, and
        # declared ahead of `resources :reports` so "citations"/"site_audit"
        # aren't read as report ids.
        patch  "reports/citations/statuses/:directory", to: "citation_statuses#update",
                                                         as: :citation_status, constraints: {directory: /[^\/]+/}
        post   "reports/site_audit/dismissals/:key", to: "site_audit_dismissals#create", as: :site_audit_dismissal,
                                                     constraints: {key: /[^\/]+/}
        delete "reports/site_audit/dismissals/:key", to: "site_audit_dismissals#destroy",
                                                     constraints: {key: /[^\/]+/}

        # `index` is the catalog with the latest of each kind, `show` one
        # stored snapshot. Running queues a fresh pull of a KIND (and spends
        # money), so it's a run of the collection, not of a snapshot.
        post "reports/:kind/run", to: "reports/runs#create", as: :run_reports
        resources :reports, only: [:index, :show, :destroy]

        namespace :settings do
          # DataForSEO credentials and the local business the reports are about.
          resource :reporting, only: [:show, :update], controller: "reportings" do
            scope module: :reportings do
              resource :test, only: :create
            end
          end
        end

        namespace :api, defaults: {format: :json} do
          # The snapshots, read-only: running one spends money and is not
          # something an agent may do (Api::ReportsController).
          resources :reports, only: [:index, :show], param: :kind
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :local_marketing, name: "Local Marketing", version: "1.0.0",
        author: "Martin Business Consultants", bundled: true, enabled_by_default: false, requires: ">= 1.0",
        description: "What search, the map pack, reviews and AI assistants see about the business: " \
                     "DataForSEO reports, an audit of the live site, and the Marketer's Report that scores " \
                     "them against targets and says what to do next. Written summaries use the AI plugin " \
                     "when it's on.",
        adopt_if: -> { Report.exists? || Setting.where(key: %w[reporting marketing]).exists? }

      Cms::Plugins.menu :local_marketing, :marketing, label: "Marketing", icon: "chart", group: "Marketing",
        group_after: "Automation", path: -> { marketing_path }, capability: "reports:read"
      Cms::Plugins.submenu :local_marketing, :marketing, label: "Marketer’s report", path: -> { marketing_path },
        capability: "reports:read"
      Cms::Plugins.submenu :local_marketing, :marketing, label: "Reports", path: -> { reports_path },
        capability: "reports:read", after: "Marketer’s report"
      Cms::Plugins.submenu :local_marketing, :marketing, label: "Settings", path: -> { settings_reporting_path },
        capability: "settings:read", after: "Reports"
      Cms::Plugins.settings :local_marketing, "Reporting", -> { settings_reporting_path },
        description: "DataForSEO and the business the reports are about.", capability: "settings:read",
        group: "Integrations", after: ["AI", "GitHub"]

      # Reporting pulls from DataForSEO, and every run is charged to the
      # site's balance there. `reports:read` is a view of public information
      # about the business; `reports:run` spends money, so it sits with the
      # roles that can already publish.
      Cms::Plugins.permissions :local_marketing, "Reports", %w[reports:read reports:run],
        after: "Recommendations", defaults: {agent: %w[reports:read]}

      Cms::Plugins.stylesheet :local_marketing, "local_marketing/local_marketing"
      # The latest site audit, in words, on the dashboard.
      Cms::Plugins.slot :dashboard, :local_marketing, "local_marketing/slots/dashboard"

      # The weekly refresh of the reports a site cares about.
      Cms::Plugins.recurring_recipe :local_marketing, "RecurringTasks::Recipes::ReportRefresh",
        after: ["submission_digest", "content_freshness_report"]

      Cms::Plugins.provide :local_marketing, :site_audit, LocalMarketing::SiteAudit

      if defined?(::Agents::Engine)
        # The reporting snapshots: what search, the map pack and the AI
        # assistants can see about the business, with trends. Read-only:
        # running a report spends money and is deliberately not an agent
        # capability (see Permissions).
        Cms::Plugins.agent_tool :local_marketing, "read_reports",
          [LocalMarketing::AgentTools::ListReports, LocalMarketing::AgentTools::GetReport],
          catalog: {group: "Read", after: "sitemap",
                    label: "Read the reporting snapshots (search, local, AI visibility, reviews)",
                    capability: "reports:read",
                    commands: ["cms reports", "cms report <kind> [--previous]"]}
      end

      Cms::Plugins.api :local_marketing, "/api/reports", description: "The reporting snapshots, read-only: the latest of each kind with how its figures moved, and any one in full."
    end
  end
end
