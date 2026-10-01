# frozen_string_literal: true

json.summary @summary
json.checks @checks.map(&:as_json)
