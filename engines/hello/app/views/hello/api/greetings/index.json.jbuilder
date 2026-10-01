# frozen_string_literal: true

json.greetings @greetings do |greeting|
  json.extract! greeting, :id, :message, :created_at
end
