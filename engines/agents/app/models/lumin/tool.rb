# frozen_string_literal: true

module Lumin
  # Base class for every tool an in-process agent run may call — the same
  # shape as the ads app's Lumin::Tool, so a tool written against one reads
  # like a tool written against the other.
  #
  # The DSL is `description`, `param`, `execute`. Nothing here talks to a
  # model: a tool is a description plus a Ruby method, and who decides to
  # call it is somebody else's problem.
  class Tool
    class << self
      # Both reader and writer, as the classic DSL is: `description "..."` in
      # a class body sets it, a bare `description` reads it.
      def description(text = nil)
        return @description if text.nil?

        @description = text.to_s.strip
      end

      def param(name, type: "string", desc: nil, required: false, **extra)
        params[name.to_sym] = {type: type.to_s, desc: desc, required: required, **extra}
      end

      # Inherited so a subclass of a subclass keeps the parent's params
      # instead of starting empty.
      def params
        @params ||= superclass.respond_to?(:params) ? superclass.params.dup : {}
      end

      # The JSON-Schema form of this tool's arguments.
      def json_schema
        {
          type: "object",
          properties: params.each_with_object({}) do |(name, spec), acc|
            acc[name] = {type: spec[:type], description: spec[:desc]}.compact
            acc[name][:enum] = spec[:enum] if spec[:enum]
            acc[name][:items] = spec[:items] if spec[:items]
          end,
          required: params.select { |_, spec| spec[:required] }.keys.map(&:to_s)
        }
      end

      # snake_case name the model calls it by.
      def tool_name = name.to_s.demodulize.underscore
    end

    def name = self.class.tool_name

    def description = self.class.description

    def json_schema = self.class.json_schema

    # Subclasses implement this. Keyword arguments, named by `param`.
    def execute(**)
      raise NotImplementedError, "#{self.class.name}#execute"
    end

    # Run the tool and normalise whatever it returns. Tools return
    # `{ error: … }` for expected failures; this is the net for the
    # unexpected, so one broken tool call comes back as a message the model
    # can react to instead of failing the whole run.
    def call(arguments = {})
      execute(**symbolize(arguments))
    rescue ArgumentError => e
      {error: "Bad arguments for #{name}: #{e.message}"}
    rescue ActiveRecord::RecordInvalid => e
      {error: "#{name} rejected: #{e.record.errors.full_messages.join("; ")}"}
    rescue StandardError => e
      Rails.logger.error("[Lumin::Tool] #{self.class.name}: #{e.class}: #{e.message}")
      {error: "#{name} failed: #{e.message}"}
    end

    private

    def symbolize(arguments)
      (arguments || {}).to_h.transform_keys(&:to_sym)
    end
  end
end
