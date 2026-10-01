# frozen_string_literal: true

module Marketing
  # The shipped business templates, loaded from config/businesses/*.yml —
  # the same arrangement as the Agents plugin's template library, for the same reason: a template
  # is behaviour, and behaviour should review in a pull request.
  module BusinessRegistry
    DIR = LocalMarketing::Engine.root.join("config/businesses")

    module_function

    def all
      @all ||= load_all
    end

    def find(key) = all[key.to_s]
    def keys = all.keys
    def ordered = all.values.sort_by { |t| t.name.downcase }

    def problems
      @problems ||= begin
        all
        @load_problems
      end
    end

    def reload!
      @all = nil
      @problems = nil
      all
    end

    # The template this site chose, if any.
    def current
      find(Setting.get(Targets::SETTING_KEY)["business_type"])
    end

    def load_all
      @load_problems = []
      templates = {}
      Dir.glob(DIR.join("*.yml")).sort.each do |path|
        begin
          template = BusinessTemplate.from_hash(YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {})
        rescue StandardError => e
          @load_problems << "#{File.basename(path)}: #{e.message}"
          next
        end
        expected = File.basename(path, ".yml")
        if template.key != expected
          @load_problems << "#{expected}.yml: key is '#{template.key}' — the file name is the key"
          next
        end
        problems = template.problems
        if problems.any?
          @load_problems << "#{expected}.yml: #{problems.join("; ")}"
          next
        end
        templates[template.key] = template
      end
      templates
    end
  end
end
