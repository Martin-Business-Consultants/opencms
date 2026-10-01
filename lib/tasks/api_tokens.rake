# frozen_string_literal: true

# Every user gets a token when their account is created, but accounts that
# predate that (and the users whose extra tokens the PersonalizeApiTokens
# migration collapsed away) need one minted. Safe to re-run — it only
# touches users with no token at all.
#
#   bin/rails api_tokens:backfill
namespace :api_tokens do
  desc "Mint the missing per-user API token for every user"
  task backfill: :environment do
    # Load the ids up front — the relation would re-query (and come back
    # empty) once the tokens exist.
    ids = User.where.missing(:api_token).pluck(:id)
    User.where(id: ids).find_each { |user| ApiToken.for(user) }
    puts "Minted #{ids.size} token(s)"
  end
end
