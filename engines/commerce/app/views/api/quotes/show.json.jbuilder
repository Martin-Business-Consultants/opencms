# frozen_string_literal: true

json.quote do
  json.partial! "api/quotes/quote", quote: @quote
end
