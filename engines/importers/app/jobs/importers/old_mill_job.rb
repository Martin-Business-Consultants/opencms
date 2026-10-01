# frozen_string_literal: true

class Importers::OldMillJob < ApplicationJob
  queue_as :default

  def perform(xml_path, dest_dir)
    Importers::Adapters::OldMill.import_now(xml_path, dest_dir)
  end
end
