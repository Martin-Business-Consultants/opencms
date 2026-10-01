# frozen_string_literal: true

json.redirect do
  json.partial! "api/redirects/redirect", redirect: @redirect
end
