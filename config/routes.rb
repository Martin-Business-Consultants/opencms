# frozen_string_literal: true

Rails.application.routes.draw do
  get  "sign_in", to: "sessions#new", as: :sign_in
  post "sign_in", to: "sessions#create"

  # Two-factor sign-in challenge — second step after username/password.
  get  "sign_in/challenge", to: "sessions#challenge", as: :sessions_challenge
  post "sign_in/challenge", to: "sessions#verify"

  get  "sign_up", to: "registrations#new", as: :sign_up
  post "sign_up", to: "registrations#create"

  # Local-agent bootstrap — `curl -fsSL https://<host>/agent/install.sh | sh`.
  # Public by design (see AgentBootstrapsController); `format: false` keeps
  # Rails from reading ".sh" / ".md" as a response format.
  get "agent/install.sh", to: "agent_bootstraps#install",   as: :agent_install, format: false
  get "agent/cms",        to: "agent_bootstraps#cli",       as: :agent_cli
  get "agent/AGENTS.md",  to: "agent_bootstraps#agents_md", as: :agent_agents_md, format: false
  get "agent/SKILL.md",   to: "agent_bootstraps#skill",     as: :agent_skill,     format: false
  # The frontend's AGENTS.md: how a site (the Astro app) works with this
  # headless CMS. The Astro integration writes it into the site's repo.
  get "frontend/AGENTS.md", to: "agent_bootstraps#frontend_md", as: :frontend_agents_md, format: false
  get "frontend/install.sh", to: "agent_bootstraps#frontend_install", as: :frontend_install, format: false
  get "frontend/files/:name", to: "agent_bootstraps#frontend_file", as: :frontend_file, format: false,
    constraints: {name: /[a-z-]+\.(ts|astro)/}

  # How frontends work with the CMS: the JSON, the Astro integration, and
  # the frontend this CMS serves.
  get "developers", to: "developers#show", as: :developers

  # Docs: guides (app/guides), the go-live checklist and site health.
  get "docs", to: "docs#index", as: :docs
  get "docs/go-live", to: "docs#go_live", as: :go_live_docs
  get "docs/site-health", to: "docs#site_health", as: :site_health_docs
  get "docs/:slug", to: "docs#show", as: :doc, constraints: {slug: /[a-z0-9-]+/}

  resources :sessions, only: [:destroy]
  # A Markdown field's Preview tab (MarkdownPreviewsController).
  resource :markdown_preview, only: :create
  namespace :users do
    resources :bulk_deletions, only: :create
  end
  resources :users, only: [:index, :new, :create, :edit, :update, :destroy]

  namespace :identity do
    resource :email_verification, only: [:show, :create]
    resource :password_reset,     only: [:new, :edit, :create, :update]
  end

  # Public sitemap for search engines. Defined ahead of the admin :sitemap
  # route so `/sitemap.xml` doesn't get matched by the admin route as
  # `index` with format=xml.
  get "sitemap.xml", to: "sitemaps#xml", as: :sitemap_xml, defaults: {format: :xml}

  get :dashboard, to: "dashboard#index"
  namespace :dashboard do
    resource :checklist_dismissal, only: :create
    resources :checklist_acknowledgements, param: :key, only: [:create, :destroy]
  end
  # The asset library. Folders are paths on assets (AssetFolders); the folder
  # resource is addressed by ?path=.
  get :file_manager,  to: "file_manager#index"
  namespace :file_manager do
    resources :assets, only: [:show, :create, :update, :destroy]
    resource :folder, only: [:create, :update, :destroy]
    resources :moves, only: :create
    resources :bulk_deletions, only: :create
    resources :bulk_uploads, only: [:create, :show]
  end

  get :sitemap,       to: "sitemaps#index", as: :sitemap, constraints: {format: /html|/}
  patch "sitemap/:source/:id", to: "sitemap_entries#update", as: :sitemap_entry,
                                constraints: {source: /page|collection_entry/}

  get "audit_log", to: "audit_logs#index", as: :audit_logs

  resources :review_requests, only: [:index, :create] do
    scope module: :review_requests do
      resource :approval, only: :create
      resource :change_request, only: :create
      resource :cancellation, only: :create
    end
  end

  # Proposed content changes from API clients that can't publish. See
  # GatedWrites — the write files one of these instead of applying.
  resources :revisions, only: [:index, :show] do
    scope module: :revisions do
      resource :approval, only: :create
      resource :rejection, only: :create
    end
  end

  # The single review queue: revisions, review requests and agent findings
  # in one place, because "what needs me?" is one question.
  get "approvals", to: "approvals#index", as: :approvals

  resources :recommendations, only: [:index, :show] do
    scope module: :recommendations do
      resource :acceptance, only: :create
      resource :dismissal, only: :create
      resource :completion, only: :create
    end
  end


  get    "trash",                       to: "trash#index",                as: :trash
  get    "trash/:kind/:id",             to: "trash#show",                 as: :trash_item
  delete "trash/:kind/:id",             to: "trash#destroy"
  post   "trash/:kind/:id/restoration", to: "trash/restorations#create",  as: :trash_item_restoration

  # Content.
  page_path_format = %r{[^/]+(?:/[^/]+)*}

  # A new block row for the content editor's "Add block" picker.
  resources :content_blocks, only: :new
  # An editor's JSON tab: the record as the API hands it to the site.
  get "api_previews/:kind/:id", to: "api_previews#show", as: :api_preview, constraints: {kind: /page|entry|global/}
  # The asset picker a content form's image fields open.
  resource :asset_picker, only: [:show, :create]
  resource :content_picker, only: :show

  namespace :pages do
    resources :bulk_deletions, only: :create
    resources :bulk_status_changes, only: :create
  end
  # Ahead of `resources :pages`: a page slug is a full path and may contain
  # slashes, so PATCH /pages/about/schema would otherwise be pages#update.
  get   "pages/:page_slug/versions", to: "pages/versions#index", as: :page_versions, constraints: {page_slug: page_path_format}
  get   "pages/:page_slug/versions/:id", to: "pages/versions#show", as: :page_version, constraints: {page_slug: page_path_format, id: /\d+/}
  post  "pages/:page_slug/versions/:version_id/restoration", to: "pages/versions/restorations#create", as: :page_version_restoration,
        constraints: {page_slug: page_path_format, version_id: /\d+/}
  get   "pages/:page_slug/schema", to: "pages/schemas#show", as: :page_schema, constraints: {page_slug: page_path_format}
  patch "pages/:page_slug/schema", to: "pages/schemas#update", constraints: {page_slug: page_path_format}
  resources :pages, param: :slug, except: :show, constraints: {slug: page_path_format}

  namespace :block_types do
    resources :bulk_deletions, only: :create
    resource :seeding, only: :create
  end
  resources :block_types, param: :slug, except: :show

  namespace :roles do
    resources :bulk_deletions, only: :create
  end
  resources :roles, only: [:index, :new, :create, :edit, :update, :destroy]

  namespace :collections do
    resources :bulk_deletions, only: :create
  end
  # The Build board, at the URL (and helper) it always had.
  get "collections/:collection_slug/entries/build", to: "collections/boards#show", as: :build_collection_entries
  resources :collections, param: :slug, except: :show do
    scope module: :collections do
      resource :schema, only: [:show, :update]
      namespace :entries do
        resources :bulk_deletions, only: :create
        resources :bulk_status_changes, only: :create
      end
    end

    resources :entries, controller: "collection_entries", param: :slug, except: :show do
      scope module: "collections/entries" do
        # A boolean flipped from the entries table, a card control edited on
        # the board, and a card dropped into a board column.
        resource :flag, only: :update
        resource :card_field, only: :update
        resource :placement, only: :create
        resources :versions, only: [:index, :show] do
          resource :restoration, only: :create, module: :versions
        end
      end
    end
  end

  namespace :globals do
    resources :bulk_deletions, only: :create
  end
  resources :globals, param: :slug, except: :show do
    resource :schema, only: [:show, :update], module: :globals
  end

  resources :webhooks do
    scope module: :webhooks do
      resource :secret_rotation, only: :create
      resource :test_delivery, only: :create
    end
  end

  # The site's branding as overrides of the admin's CSS tokens.
  get "branding.css", to: "branding_stylesheets#show", as: :branding_stylesheet, format: false

  get "settings", to: "settings/sections#index", as: :settings
  namespace :settings do
    resource :general, only: [:show, :update], controller: "generals"
    resource :profile, only: [:show, :update, :destroy]
    resource :password, only: [:show, :update]
    resource :email, only: [:show, :update]
    # One token per user: nothing to create or destroy, only read and roll.
    resource :api_token, only: [:show], controller: "api_tokens" do
      scope module: :api_tokens do
        resource :reveal, only: :create
        resource :rotation, only: :create
      end
    end
    # Credentials for machines rather than people: the published site, a
    # build, an agent. Many per site, each with its own role.
    resources :service_tokens, only: [:index, :create] do
      scope module: :service_tokens do
        resource :reveal, only: :create
        resource :rotation, only: :create
        resource :revocation, only: :create
      end
    end
    resource :branding, only: [:show, :update]
    # Brand *context* — the written brief (voice, audience, facts, style)
    # published to agents via /api/manifest. Distinct from :branding above,
    # which is the visual identity.
    resource :brand, only: [:show, :update], controller: "brands"
    resource :two_factor, only: [:show, :destroy], controller: "two_factors" do
      scope module: :two_factors do
        resource :activation, only: :create
        resource :recovery_codes, only: :create
      end
    end
    resource :github, only: [:show, :update], controller: "githubs"
    resource :deploy, only: [:show, :update], controller: "deploys" do
      scope module: :deploys do
        resource :trigger, only: :create
      end
    end
    # This install's version and the newest release; create updates to it
    # (Upgrade), and check asks GitHub now.
    resource :updates, only: [:show, :create] do
      scope module: :updates do
        resource :check, only: :create
      end
    end
    resources :sessions, only: [:index]
    resource :appearance, only: [:show], controller: "appearances"
    # What this install adds (Cms::Plugins); create/destroy switch one on/off.
    resources :plugins, only: [:index, :show], param: :key do
      scope module: :plugins do
        resource :activation, only: [:create, :destroy]
      end
    end
  end

  namespace :tools do
    namespace :redirects do
      resource :export, only: :show
      resource :import, only: :create
      resources :bulk_deletions, only: :create
    end
    resources :redirects, except: :show

    # Tools › Schedules; :id is the recipe key. A run is queued right away.
    resources :recurring_tasks, only: [:index, :edit, :update] do
      scope module: :recurring_tasks do
        resource :run, only: :create
      end
    end

    # Tools › Backup: download one now, or an archive bin/update left.
    resource :backup, only: [:show, :create] do
      scope module: :backups do
        resources :archives, only: :show, param: :name, format: false,
          constraints: {name: /cms-data-\d{8}-\d{6}\.tar\.gz/}
      end
    end
  end
  get :tools, to: redirect("/tools/backup")

  # Device login: `cms login` sends someone here to approve their terminal.
  get  "connect", to: "device_approvals#new"
  post "connect", to: "device_approvals#create"

  namespace :api, defaults: {format: :json} do
    # The guides and the go-live checklist, for the CLI and MCP (`cms docs`, `cms go-live`).
    get "docs", to: "docs#index"
    get "docs/:slug", to: "docs#show", as: :doc, constraints: {slug: /[a-z0-9-]+/}
    get "go_live", to: "go_lives#show"
    get "site_health", to: "site_healths#show"

    # The frontend this CMS serves, and its build reporting that it ran (Frontend).
    resource :frontend, only: :show
    namespace :frontend do
      resources :builds, only: :create
    end

    # The CLI's device-login handshake — unauthenticated by design, since it is
    # how a machine gets its first credential.
    post "device/code",  to: "device_authorizations#create"
    post "device/token", to: "device_authorizations#token"

    get  "manifest",   to: "manifest#show"
    get  "references", to: "references#index"
    post "search",     to: "searches#create"

    # Sitemap: #show is the build-facing payload, #entries and #update are
    # the admin tree and its per-row patch endpoint.
    get   "sitemap",                to: "sitemap#show"
    get   "sitemap/entries",        to: "sitemap_entries#index"
    patch "sitemap/:source/:id",    to: "sitemap_entries#update",
                                    constraints: {source: /page|collection_entry/}

    # Redirects: index/resolve are the edge-facing reads; the rest mirrors
    # Tools › Redirects. `all` is separate from `index` so the build payload
    # keeps its shape.
    get    "redirects",         to: "redirects#index"
    get    "redirects/resolve", to: "redirects/resolutions#show"
    get    "redirects/all",     to: "redirects/rules#index"
    get    "redirects/export",  to: "redirects/exports#show"
    post   "redirects/import",  to: "redirects/imports#create"
    resources :redirects, only: [:create, :update, :destroy]

    resources :settings, param: :key, only: [:index, :show, :create, :update, :destroy]

    resources :preview_drafts, only: [:show, :create, :update], param: :token

    # Deploy hook — Settings › Deploy.
    get   "deploy",         to: "deploys#show"
    patch "deploy",         to: "deploys#update"
    post  "deploy/trigger", to: "deploys/triggers#create"

    # Settings › Updates, read-only: starting an update is the admin's alone.
    get  "updates",       to: "updates#show"
    post "updates/check", to: "updates/checks#create"

    get "audit_log", to: "audit_logs#index"

    # Trash. `kind` is one of the kinds Trash lists (page, entry, global, asset,
    # and those plugins add).
    get    "trash",                   to: "trash#index"
    post   "trash/:kind/:id/restore", to: "trash/restorations#create", as: :trash_item_restoration
    delete "trash/:kind/:id",         to: "trash#destroy",             as: :trash_item

    resources :review_requests, only: [:index, :create]
    post "review_requests/:review_request_id/approve",         to: "review_requests/approvals#create",       as: :review_request_approval
    post "review_requests/:review_request_id/request_changes", to: "review_requests/change_requests#create", as: :review_request_change_request
    post "review_requests/:review_request_id/cancel",          to: "review_requests/cancellations#create",   as: :review_request_cancellation

    # What an agent files when it finds something it can't fix itself.
    resources :recommendations, only: [:index, :show, :create]


    # Declared ahead of `resources :pages` on purpose: a page slug is a full
    # path and may contain slashes, so `PATCH /api/pages/about/schema` would
    # otherwise match pages#update with slug="about/schema".
    patch "pages/:page_slug/schema", to: "pages/schemas#update", as: :schema_api_page,
                                     constraints: {page_slug: %r{[^/]+(?:/[^/]+)*}}
    post "pages/bulk_destroy",       to: "pages/bulk_deletions#create", as: :bulk_destroy_pages
    post "pages/bulk_update_status", to: "pages/bulk_status_changes#create", as: :bulk_update_status_pages

    resources :pages, param: :slug, only: [:index, :show, :create, :update, :destroy],
                      constraints: {slug: %r{[^/]+(?:/[^/]+)*}}

    resources :assets, only: [:index, :create, :show, :update, :destroy]
    # Folders are paths on assets, not records: one resource, addressed by path.
    resource  :asset_folders, only: [:create, :update, :destroy]
    resources :bulk_uploads, only: [:create, :show]

    # Declared ahead of `resources :globals` so the verb isn't read as a
    # global's slug. The URLs are the ones the CLI has always called; the
    # controllers are resources (Api::Globals::…).
    post "globals/bulk_destroy", to: "globals/bulk_deletions#create", as: :bulk_destroy_globals

    resources :globals, param: :slug, only: [:index, :show, :create, :update, :destroy] do
      scope module: :globals do
        patch "schema", to: "schemas#update", as: :schema
      end
    end

    # Declared ahead of `resources :collections` so the verb isn't read as a
    # collection slug. The URLs are the ones the CLI has always called; the
    # controllers are resources (Api::Collections::…).
    post "collections/bulk_destroy", to: "collections/bulk_deletions#create", as: :bulk_destroy_collections

    resources :collections, param: :slug, only: [:index, :show, :create, :update, :destroy] do
      scope module: :collections do
        patch "schema", to: "schemas#update", as: :schema
        post "entries/bulk_destroy",       to: "entries/bulk_deletions#create",      as: :bulk_destroy_entries
        post "entries/bulk_update_status", to: "entries/bulk_status_changes#create", as: :bulk_update_status_entries
      end

      resources :entries,
                controller: "collection_entries",
                param: :slug,
                only: [:index, :show, :create, :update, :destroy] do
        scope module: "collections/entries" do
          # One key merged into the frontmatter, and a Build board move.
          patch :toggle_field, to: "flags#update"
          patch :update_field, to: "card_fields#update"
          patch :move,         to: "placements#update"
        end
      end
    end

    # The same for block types (Api::BlockTypes::…).
    post "block_types/bulk_destroy", to: "block_types/bulk_deletions#create", as: :bulk_destroy_block_types
    post "block_types/seed",         to: "block_types/seedings#create",       as: :seed_block_types

    resources :block_types, param: :slug, only: [:index, :show, :create, :update, :destroy]

    resources :webhooks, only: [:index, :show, :create, :update, :destroy]
    post "webhooks/:webhook_id/rotate_secret", to: "webhooks/secret_rotations#create", as: :webhook_secret_rotation
    post "webhooks/:webhook_id/test",          to: "webhooks/test_deliveries#create",  as: :webhook_test_delivery
    get  "webhooks/:webhook_id/deliveries",    to: "webhooks/deliveries#index",        as: :webhook_deliveries

    namespace :tools do
      resources :recurring_tasks, only: [:index, :update]
      post "recurring_tasks/:recurring_task_id/run_now", to: "recurring_tasks/runs#create", as: :recurring_task_run

      get  "backup", to: "backups#show"
      post "backup", to: "backups#create"
    end

    get  "api_tokens/me",     to: "api_tokens/identities#show", as: :me_api_tokens
    post "api_tokens/rotate", to: "api_tokens/rotations#create", as: :rotate_api_tokens

    # Settings › Service tokens, for the CLI. Reveal/rotate/revoke are POSTs
    # rather than GETs because each one is an event worth auditing, not a read.
    resources :service_tokens, only: [:index, :show, :create]
    post "service_tokens/:service_token_id/reveal", to: "service_tokens/reveals#create",     as: :service_token_reveal
    post "service_tokens/:service_token_id/rotate", to: "service_tokens/rotations#create",   as: :service_token_rotation
    post "service_tokens/:service_token_id/revoke", to: "service_tokens/revocations#create", as: :service_token_revocation
  end

  root "home#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
