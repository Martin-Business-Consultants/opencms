# frozen_string_literal: true

# Renamed to Importers::WordpressJob. Kept one release so jobs queued under the old name still
# run; remove after.
class WordpressImportJob < Importers::WordpressJob
end
