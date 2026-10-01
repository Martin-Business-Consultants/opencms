# frozen_string_literal: true

json.redirects @redirects, partial: "api/redirects/redirect", as: :redirect
json.status_codes Redirect::STATUS_CODES
