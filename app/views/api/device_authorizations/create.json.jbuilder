# frozen_string_literal: true

json.status "ok"
json.user_code @authorization.user_code
json.device_code @authorization.device_code
json.verification_url connect_url(code: @authorization.user_code)
json.interval Api::DeviceAuthorizationsController::POLL_INTERVAL
json.expires_in (@authorization.expires_at - Time.current).to_i
json.account Site.key
