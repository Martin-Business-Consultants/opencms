# frozen_string_literal: true

json.merge!({ok: true, queued: true, source: params[:source], **@queued.api.to_h, message: @queued.api_message})
