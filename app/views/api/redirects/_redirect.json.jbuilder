# frozen_string_literal: true

json.extract! redirect, :id, :source_path, :destination_url, :status_code, :active, :wildcard,
  :hit_count, :last_hit_at, :notes, :created_at, :updated_at
