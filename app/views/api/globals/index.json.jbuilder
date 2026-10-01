# frozen_string_literal: true

json.globals @globals, partial: "api/globals/global", as: :record
json.assets @assets if @assets
