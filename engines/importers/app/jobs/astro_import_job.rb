# frozen_string_literal: true

# Renamed to Importers::AstroJob. Kept one release so jobs queued under the old name still
# run; remove after.
class AstroImportJob < Importers::AstroJob
end
