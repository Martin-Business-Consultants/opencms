# frozen_string_literal: true

json.recommendations @recommendations, partial: "api/recommendations/recommendation", as: :record
