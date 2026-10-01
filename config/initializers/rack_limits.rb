# frozen_string_literal: true

# Room for a large content form. The page, entry and global editors post one
# field per control and one per block or repeater row, so a long page can go
# past Rack's default of 4096 parameters and be refused outright. Turbo posts
# FormData, which is multipart, so the multipart part count needs the same
# room as a urlencoded form's parameter count.
#
# Rack's own environment variables still win (RACK_QUERY_PARSER_PARAMS_LIMIT,
# RACK_MULTIPART_TOTAL_PART_LIMIT). The body-size limit and the uploaded-file
# limit are left at Rack's defaults.
CONTENT_FORM_PARAMS_LIMIT = 20_000

unless ENV.key?("RACK_QUERY_PARSER_PARAMS_LIMIT")
  Rack::Utils.default_query_parser = Rack::QueryParser.make_default(
    Rack::Utils.default_query_parser.param_depth_limit,
    params_limit: CONTENT_FORM_PARAMS_LIMIT
  )
end

Rack::Utils.multipart_total_part_limit = CONTENT_FORM_PARAMS_LIMIT unless ENV.key?("RACK_MULTIPART_TOTAL_PART_LIMIT")
