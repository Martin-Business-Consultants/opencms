# frozen_string_literal: true

# Tools › Redirects › Export: every rule as CSV (Redirect::Portable).
class Tools::Redirects::ExportsController < ApplicationController
  requires_capability "redirects:read", only: :show

  def show
    send_data Redirect.to_csv, filename: Redirect.csv_filename, type: "text/csv"
  end
end
