# frozen_string_literal: true

require "commerce/engine"

# Commerce: selling by quotation. A product page posts a quote request, the
# shop works it in Commerce › Quote requests, drafts an invoice from it, sends
# it, and marks it paid. The CMS never moves money — an invoice carries the
# payment link the shop's processor issued. Bundled and off by default.
#
# Its models keep the names and tables they had in the core (quote_requests,
# invoices) — they predate plugins; a new table would be prefixed.
module Commerce
end
