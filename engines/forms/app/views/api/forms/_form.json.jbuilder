# frozen_string_literal: true

json.merge! record.as_json(only: %i[id slug title status fields submit_url submit_label success_message
  notify_emails notify_webhook_url webhook_body created_at updated_at])
