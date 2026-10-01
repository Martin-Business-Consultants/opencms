# frozen_string_literal: true

json.guide do
  json.slug @guide.slug
  json.title @guide.title
  json.summary @guide.summary
  json.markdown @guide.markdown(cms_url: request.base_url)
end
