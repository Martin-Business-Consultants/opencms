# frozen_string_literal: true

module Agents
  # The shipped agent library, loaded from config/agents/*.yml.
  #
  # It lives in the repo rather than in each install's database because a
  # template is behaviour, and behaviour should be reviewable in a pull
  # request, versioned by git, and eval'd in CI. The old arrangement seeded
  # eight Ruby hashes into every install, after which improving one reached
  # nobody: each install held a private copy of the prose as it read on the day
  # they pressed Load.
  #
  # A site still owns its rows — editing an agent is expected here, and a
  # seed never overwrites an edit (Agents::TemplateLibrary). What the registry
  # adds is that the library can move on and SAY so, per agent, with the
  # change visible before anyone takes it.
  module Registry
    DIR = Agents::Engine.root.join("config/agents")

    module_function

    def all
      @all ||= load_all
    end

    def find(key) = all[key.to_s]

    def keys = all.keys

    def ordered = all.values.sort_by { |t| [t.category.to_s, t.name.to_s.downcase] }

    # Files the registry could not parse or that failed validation. Loud in
    # CI, invisible at runtime: a bad template must not take a site's agents
    # page down with it.
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

    def load_all
      @load_problems = []
      templates = {}

      Dir.glob(DIR.join("*.yml")).sort.each do |path|
        template = load_file(path)
        next if template.nil?

        expected = File.basename(path, ".yml")
        if template.key != expected
          @load_problems << "#{expected}.yml: key is '#{template.key}' — the file name is the key"
          next
        end
        @load_problems << "#{expected}.yml: #{template.errors.join("; ")}" unless template.valid?
        templates[template.key] = template
      end

      templates.freeze
    end

    def load_file(path)
      Template.from_hash(YAML.safe_load_file(path))
    rescue StandardError => e
      @load_problems << "#{File.basename(path)}: #{e.class}: #{e.message}"
      nil
    end
  end
end
