# frozen_string_literal: true

module Commerce
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    # The public and API paths are the ones the sites and the CLI already use.
    initializer "commerce.routes" do |app|
      app.routes.append do
        namespace :quote_requests, path: "quotes" do
          resources :bulk_deletions, only: :create
        end
        resources :quote_requests, path: "quotes", only: [:index, :show, :update, :destroy]

        resources :invoices do
          scope module: :invoices do
            resource :delivery, only: :create
            resource :payment, only: :create
            resource :voiding, only: :create
          end
        end
        # The hosted customer view of an invoice, addressed by its unguessable token.
        get "i/:token", to: "public_invoices#show", as: :public_invoice

        namespace :settings do
          # Who gets quote requests, how invoices are numbered and signed.
          resource :commerce, only: [:show, :update], controller: "commerces"
        end

        namespace :api, defaults: {format: :json} do
          # The public write path a product page posts to, then the
          # authenticated inbox and the invoices the shop sends back.
          post    "quote_requests", to: "quote_requests#create"
          options "quote_requests", to: "quote_requests#options"
          resources :quotes, controller: "quotes", only: [:index, :show, :create, :update, :destroy]

          resources :invoices, only: [:index, :show, :create, :update, :destroy]
          post "invoices/:id/send",      to: "invoices/deliveries#create"
          post "invoices/:id/mark_paid", to: "invoices/payments#create"
          post "invoices/:id/void",      to: "invoices/voidings#create"
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :commerce, name: "Commerce", version: "1.0.0", author: "Martin Business Consultants",
        bundled: true, enabled_by_default: false, requires: ">= 1.0",
        description: "Selling by quotation: the “request a quote” endpoint a product page posts to, the " \
                     "quote inbox, and the invoices the shop drafts, sends and marks paid.",
        adopt_if: -> { QuoteRequest.exists? || Invoice.exists? }

      Cms::Plugins.menu :commerce, :commerce, label: "Commerce", icon: "receipt", group: "Commerce",
        group_after: "Content", path: -> { quote_requests_path }, capability: "quotes:read"
      Cms::Plugins.submenu :commerce, :commerce, label: "Quote requests", path: -> { quote_requests_path },
        capability: "quotes:read"
      Cms::Plugins.submenu :commerce, :commerce, label: "Invoices", path: -> { invoices_path },
        capability: "invoices:read", after: "Quote requests"
      Cms::Plugins.submenu :commerce, :commerce, label: "Add invoice", path: -> { new_invoice_path },
        capability: "invoices:write", after: "Invoices"
      Cms::Plugins.submenu :commerce, :commerce, label: "Settings", path: -> { settings_commerce_path },
        capability: "invoices:read", after: "Add invoice"
      Cms::Plugins.new_item :commerce, label: "Invoice", path: -> { new_invoice_path }, capability: "invoices:write"
      Cms::Plugins.settings :commerce, "Commerce", -> { settings_commerce_path },
        description: "Quote requests and invoices.", capability: "invoices:read",
        group: "Workspace", after: "Brand context"
      # `invoices:send` is its own capability because sending emails a
      # customer — drafting one is reversible, sending it is not.
      Cms::Plugins.permissions :commerce, "Commerce",
        %w[quotes:read quotes:write quotes:delete invoices:read invoices:write invoices:send invoices:delete],
        after: ["Forms", "Globals"],
        defaults: {editor: %w[quotes:read quotes:write quotes:delete invoices:read invoices:write invoices:send invoices:delete],
                   author: %w[quotes:read invoices:read],
                   agent: %w[quotes:read quotes:write invoices:read]}
      Cms::Plugins.stylesheet :commerce, "commerce/commerce"

      Cms::Plugins.counts :commerce, after: [:submissions, :globals], backup: false,
        quote_requests: -> { QuoteRequest.count }, invoices: -> { Invoice.count }
      # Where a product page posts a request, and what the shop has set up —
      # there whenever Commerce is on, so a site can wire the button unasked.
      Cms::Plugins.manifest_section :commerce, :commerce, -> {
        settings = Setting.get("commerce")
        {quote_endpoint: "/api/quote_requests", currency: settings["currency"].presence || "USD",
         configured: settings["notification_recipients"].present?}
      }, after: :counts
      Cms::Plugins.webhook_events :commerce, "Commerce", %w[quote_request.created invoice.sent invoice.paid],
        after: "submission.created"

      Cms::Plugins.api :commerce, "/api/quote_requests", description: "Where a product page posts a quote request (public, CORS)."
      Cms::Plugins.api :commerce, "/api/quotes", description: "The quote inbox: read, work and add requests."
      Cms::Plugins.api :commerce, "/api/invoices", description: "Invoices: draft (from a quote), send, mark paid, void."
    end
  end
end
