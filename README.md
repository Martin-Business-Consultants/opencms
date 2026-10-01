# LibrePublish CMS

A headless CMS built on Rails: an admin that edits like WordPress, a JSON API
that does everything the admin does, a `cms` CLI and MCP surface for AI
agents, and plugins. One install is one site, in one container, with SQLite
for everything. Sites render the content with any frontend, starting with
Astro (`integrations/astro`).

```sh
mise install      # ruby 4.0.6
bin/setup         # gems, databases, seeds, then bin/dev
                  # http://localhost:3000, sign in as alice@site.test / password1234
bin/ci            # rubocop, herb lint, bundler-audit, brakeman, rspec, seeds
```

- `docs/install.md`: running your own, with Kamal (or Hoster) or as a plain
  checkout, and updating it.
- `docs/plugins.md`: extending it. `engines/hello` is the reference plugin.
- `docs/vision.md`: what it is for and how it is put together.
- `docs/agent-interface.md`: the API, CLI and MCP surface agents use.
- `CHANGELOG.md`: every release.

Releases are `vX.Y.Z` tags at
https://github.com/Martin-Business-Consultants/opencms/releases; an install
offers each one in Settings › Updates.

Licensed under the Functional Source License (FSL-1.1-MIT, `LICENSE.md`): use
it, change it and run it for yourself or your clients, but not to offer a
competing product. Each release becomes MIT two years after it's published.
