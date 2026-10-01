# frozen_string_literal: true

json.status "ok"
json.token @plaintext
json.purpose @site ? "site" : "user"
json.token_name @issued.name if @site
json.user do
  json.name @user.name
  json.email @user.email
end
json.account Site.key
json.api_url request.base_url
