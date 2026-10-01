# frozen_string_literal: true

require "fileutils"

module Importers
  # One source content can be imported from. Register a subclass with
  # `Cms::Plugins.importer :<plugin>, "<key>", MyAdapter`; Tools › Import gives it
  # a tab with its `form_partial` (posting to tools_import_run_path(key)), and
  # POST /api/tools/import/<key> runs it. Imports are asynchronous: #queue
  # stages what it was given, enqueues the work and says so.
  #
  #   class Ghost < Importers::Adapter
  #     def self.label = "Ghost"
  #     def self.description = "A Ghost JSON export."
  #     def self.form_partial = "ghost/import_form"
  #
  #     def queue
  #       file = params[:file]
  #       raise Invalid.new("Pick a Ghost export.", api_message: "Attach a Ghost export as the `file` param") unless file.respond_to?(:read)
  #       …
  #       Queued.new(notice: "Ghost import queued.", api_message: "Import queued.")
  #     end
  #   end
  class Adapter
    # What went wrong, said to a person on the page (message) and to an API
    # caller (api_message, with an error code).
    class Invalid < StandardError
      attr_reader :api_message, :code

      def initialize(message, api_message: message, code: "invalid")
        super(message)
        @api_message = api_message
        @code = code
      end
    end

    # notice: the flash on Tools › Import. api_message and api: the API's
    # message and what it adds to the 202 before it ({detected: …}). audit:
    # extra detail for the import.queued audit entry.
    Queued = Struct.new(:notice, :api_message, :api, :audit, keyword_init: true)

    class << self
      def key = name.demodulize.underscore
      def label = name.demodulize
      def description = ""
      def form_partial = nil
    end

    attr_reader :params

    def initialize(params)
      @params = params
    end

    def queue
      raise NotImplementedError, "#{self.class} must implement #queue"
    end

    private

    # storage/imports/<key>-<time>/, where an upload waits for its job.
    def staging_dir
      dir = Pathname(Importers.staging_path).join("#{self.class.key}-#{Time.current.strftime("%Y%m%d-%H%M%S")}")
      FileUtils.mkdir_p(dir)
      dir
    end
  end
end
