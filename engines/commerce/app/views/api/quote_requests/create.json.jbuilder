# frozen_string_literal: true

json.ok true
json.id @quote.id
json.success_message Setting.get("commerce")["success_message"].presence
