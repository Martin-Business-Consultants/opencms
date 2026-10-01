# frozen_string_literal: true

# Renamed to Importers::DirectusJob. Kept one release so jobs queued under the old name still
# run; remove after.
class DirectusImportJob < Importers::DirectusJob
end
