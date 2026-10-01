# Installing and updating the CMS

One install serves one site: its own process, databases, uploaded files and
secrets, reached at its own hostname. Everything the install stores lives in
one data directory (`CMS_DATA_DIR`), so backing up that directory and the
install's secrets backs up the site.

There are two ways to run one: Kamal (Docker, the default) or a plain
checkout with `bin/install`.

## What an install is configured with

| Variable | What it is |
|---|---|
| `APP_HOST` | The address people and the API use (`acme.librepublish.com`). Links in email, the `cms` CLI and agent bootstraps are built from it. |
| `SITE_KEY` | What the API calls the site — the `tenant` field of webhook envelopes, `/api/manifest` and device login, which Lumin matches on (`Site#cms_key`). Defaults to the first label of `APP_HOST`. Keep it when a site changes host. |
| `CMS_DATA_DIR` | Databases (`production.sqlite3`, `_cache`, `_queue`, `_cable`), Active Storage files, and `backups/`. Default `storage/` in the app. |
| `SECRET_KEY_BASE`, `AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY`, `AR_ENCRYPTION_KEY_DERIVATION_SALT` | The install's secrets. Losing them loses the sessions and every encrypted value (API tokens, integration keys). Without the `AR_ENCRYPTION_*` keys, encryption keys derive from `SECRET_KEY_BASE`. |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | Outbound mail. The address, port and username default to Outsend's relay (`smtp.getoutsend.com`, 2587, `outsend`); the password is its API key. |
| `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME` | The sender of the install's own mail (password resets, invitations), and the fallback for the site's. Default `noreply@<APP_HOST>`, `LibrePublish`. |
| `APP_PROTOCOL` | `https` (default) or `http`, for links. |
| `CMS_BACKUP_KEEP`, `CMS_BACKUP_DIR` | How many data backups to keep (5) and where (`$CMS_DATA_DIR/backups`). |
| `ASSUME_SSL` | `true` behind a proxy that terminates TLS (Cloudflare, a load balancer). |
| `CMS_PLUGINS` | The install's plugins, for a Docker build (see Plugins below). |
| `CMS_RELEASES_REPO`, `CMS_RELEASES_TOKEN` | Where the daily update check looks (default `Martin-Business-Consultants/opencms`), and a token if that repo is private. |
| `CMS_UPDATE_CHECK` | `false` stops the daily check for a newer release. |
| `CMS_UPDATES` | How Settings › Updates updates: `local` (bin/update), `hoster` (a deploy proposed to Hoster), `github` (the Deploy workflow) or `manual` (shows the command). Worked out from the install when unset. |
| `CMS_HOSTER_URL`, `CMS_HOSTER_TOKEN`, `CMS_HOSTER_ENVIRONMENT_ID` | For an install Hoster deploys: where Hoster is, an API token that may propose changes, and the install's environment there. |
| `CMS_GITHUB_TOKEN`, `CMS_DEPLOY_DESTINATION`, `CMS_DEPLOY_WORKFLOW` | For a Docker install updating itself: a token that may start the Deploy workflow, the site's destination, and the workflow file (`deploy.yml`). |

## Kamal

`config/deploy.yml` is what every install shares and names no server,
hostname or secret; each site is a destination over it, and every Kamal
command names one (`require_destination`).

1. Copy `config/deploy.example-site.yml` to `config/deploy.<site>.yml` and set
   its `service` (`cms-<site>`), server, `APP_HOST`, `SITE_KEY`, `proxy.host`
   and volume (`cms_<site>_storage`). Several sites can share a server.
2. Copy `.kamal/secrets.example-site` to `.kamal/secrets.<site>` and point it
   at the site's secrets in your password manager. Neither file is
   committed.
3. `kamal setup -d <site>` once, then `kamal deploy -d <site>` for every
   release.

## Hoster

Hoster runs Kamal for you against this repository: it reads
`config/deploy.yml` and `.kamal/secrets-common`, and writes each
environment's destination from its hosts, domains, variables and secrets.

1. Add the repository as an app **named for the site** (`cms-acme`). Kamal
   names the service, and so the data volume (`cms-acme_storage`), after the
   app. Two environments of one app on the same server would share a volume,
   and with it every database, so Hoster refuses to deploy the second.
2. Attach a server and a domain to its environment.
3. Variables: `APP_HOST`, `SITE_KEY`, `MAIL_FROM_ADDRESS`, and
   `ASSUME_SSL=true` behind Cloudflare.
4. Secrets: `SECRET_KEY_BASE` and the three `AR_ENCRYPTION_*` keys for a new
   site, or only `SECRET_KEY_BASE` (the old install's) for one moved from the
   old shared install; `SMTP_PASSWORD`; `CMS_PLUGINS` if it has plugins.
5. So Settings › Updates can update it: `CMS_HOSTER_URL`, `CMS_HOSTER_TOKEN`
   (a Hoster API token with write access, as a secret) and
   `CMS_HOSTER_ENVIRONMENT_ID`. Update then proposes deploying the release's
   tag; Hoster's API only proposes, so the deploy runs once someone approves
   it in Hoster, and the page links there. An environment can instead deploy
   every new tag by itself.

A site already running on the server comes in with Hoster's import, which
keeps its service, destination and volume rather than starting on an empty
one.

On boot the container backs up the data directory (`bin/rails cms:backup`),
then runs `db:prepare`: an empty volume gets the site's starter roles, block
types, settings and globals — never the demo seed — and an existing one is
migrated. Open `https://<host>/sign_up` to create the owner, or
`kamal app exec -d <site> 'bin/rails cms:bootstrap[owner@acme.com]'`, which
prints the owner's password and the site's two machine tokens once.

## A plain install

From a checkout of a release (`git clone … && git checkout v1.0.0`):

    bin/install --host acme.example.com [--site-key acme] [--data-dir /var/lib/cms] [--port 3000]
                [--admin-email owner@acme.com --admin-name "Ann Owner"]

It installs the production gems, writes `.env` with fresh secrets (only if
there isn't one; mode 600), prepares the database and compiles assets. With
`--admin-email` it creates the owner and prints the password once; otherwise
the first visit to `/sign_up` does. Run it with
`set -a; . ./.env; set +a; bin/thrust bin/rails server`, or as a service with
`config/cms.service`.

## Updating

A release is a `vX.Y.Z` tag. The install checks for a newer one daily, and
Settings › Updates shows it with its notes and an **Update** button. The
button works one of three ways, depending on how the install runs
(`CMS_UPDATES` forces one):

- **A plain install** (a checkout with a `.env`) runs `bin/update <tag>` in
  the background: back up the data directory, fetch and check out the
  release, bundle, migrate, compile assets, restart Puma. Its output goes to
  `$CMS_DATA_DIR/updates/<n>/update.log`.
- **An install Hoster deploys** proposes the deploy to Hoster (see Hoster
  above).
- **A Kamal install** starts the repository's **Deploy** workflow
  (`.github/workflows/deploy.yml`), which runs `kamal deploy -d <site>` on
  GitHub. Set `CMS_GITHUB_TOKEN` (a fine-grained token on the repository:
  Contents read, Actions read and write) and `CMS_DEPLOY_DESTINATION`. On
  GitHub, make an environment named for the site holding
  `DEPLOY_DESTINATION_YML` (its `config/deploy.<site>.yml`),
  `SSH_PRIVATE_KEY` and the secrets its destination names.

The page follows the update and says when the install runs the new version,
or why it failed; until then the old version keeps running. Without either,
it shows the command. By hand:

    bin/update             # the code that's checked out (after your own git pull)
    bin/update v1.1.0      # fetch and check out that release first
    kamal deploy -d <site> # a Kamal install, from a checkout of the release

`bin/update` stops at the first step that fails (under systemd, restart with
`sudo systemctl restart cms`).

Migrations have to be safe on a live install and on an older version still
running beside a newer database: add columns and tables in one release, and
remove or rename them only in a later one, once nothing reads them.

## Backups and restoring

`bin/rails cms:backup` writes `backups/cms-data-<time>.tar.gz` in the data
directory: every database (copied with SQLite's online backup, so it's
consistent while the app runs) and every uploaded file, keeping the newest
five. bin/update and every container boot take one. Tools › Backup lists them
for anyone with `tools:use` to download. Copy them off the server with the
install's secrets — a backup without its `SECRET_KEY_BASE` can't decrypt its
tokens.

To restore: stop the app, move the data directory aside, unpack the archive
into an empty one (`tar -xzf cms-data-….tar.gz -C "$CMS_DATA_DIR"`), start the
app. Tools › Backup is a different thing: a portable JSON export of the
content.

## Releasing

Add notes under `## Unreleased` in `CHANGELOG.md` as you go, then from a clean
`main`:

    bin/release 1.1.0

It moves the Unreleased notes under `## 1.1.0`, writes `VERSION`, commits,
tags `v1.1.0` and pushes. `.github/workflows/release.yml` publishes the GitHub
release with that section as its notes, which is what every install's update
check reads.

## Plugins

Bundled plugins ship in `engines/` and are switched on in Settings › Plugins.
Others are git repositories. A plain install adds them with
`bin/rails "plugins:install[url,ref]"` (docs/plugins.md). A Docker install
clones its repository fresh for every build, so it lists them instead, in the
`CMS_PLUGINS` builder secret, and the image build fetches them
(`bin/fetch-plugins`) before bundling:

    CMS_PLUGINS="https://github.com/org/cms-seo#v1.2.0 https://x-access-token:TOKEN@github.com/org/private-thing"

Each is a git URL with an optional `#tag` or branch, separated by spaces,
commas or newlines; `none` or empty installs nothing. It is a secret so a
private plugin's URL can carry a token without it reaching the image. Set it
in `.kamal/secrets.<site>`, as a Hoster secret, or as a GitHub environment
secret for the Deploy workflow, then deploy.

## Rebuilding the public site on publish

With Settings › Deploy set to GitHub, publishing sends the site repo a
`repository_dispatch` event of type `cms-publish`. The repo needs a workflow
that listens for it: copy `integrations/astro/.github/workflows/cms-publish.yml`
into the site's `.github/workflows/`, set its `CMS_BASE_URL` and
`CMS_API_TOKEN` (the read-only Production site token) repository secrets, and
replace its placeholder deploy step with the host's (Cloudflare Pages,
Netlify and GitHub Pages are sketched in comments). The GitHub token in
Settings › GitHub needs `contents: write` on that repo to send the event.

## Moving a site from the shared deployment

The old deployment kept one SQLite database per tenant
(`storage/production/<tenant>/main.sqlite3`), Active Storage keys prefixed
`<tenant>/`, and the files under `storage/<tenant>/`. One site moves into its
own, fresh install with

    bin/rails "cms:import_tenant[PATH]"

run on the new install (on Kamal, `kamal app exec -d <site> -i 'bin/rails …'`
with PATH on the volume). PATH is a directory holding copies of:

| | |
|---|---|
| `main.sqlite3` (and `-wal`, `-shm` if there are any) | The tenant's database. Required. |
| `global.sqlite3` | The old global database — where the owner's email comes from. Optional. |
| `files/` | The tenant's `storage/<tenant>/` directory (also found as `PATH/<tenant>/` or `PATH/storage/<tenant>/`). |

The task copies the database and checkpoints the copy (it never writes to
PATH), puts it in place of the install's database (the one it replaces stays
beside it as `production.sqlite3.before-import-<time>`), runs the migrations
it's behind on, strips the `<tenant>/` prefix from blob keys, copies each file
to where this install looks for it and checks its checksum, and gives the old
owner the Admin role. Then it reads every encrypted value and names the
columns it couldn't decrypt, and prints a summary: migrations run, blobs
copied or missing, the owner, and a count of each table.

| Variable | |
|---|---|
| `DRY_RUN=1` | Say what would happen and change nothing. |
| `FORCE=1` | Import into an install that already has users (replacing its database). Without it the task refuses. Re-running with it starts again from PATH, so it lands the same. |
| `TENANT` | The old subdomain, if it can't be told from the blob keys or the global database. |
| `SITE_KEY` | Defaults to the tenant. |
| `FILES` | The files directory, if it isn't in one of the places above. |

Before and after:

- Give the install the old deployment's `SECRET_KEY_BASE` and **no**
  `AR_ENCRYPTION_*` of its own, so its encrypted API
  tokens and integration keys stay readable. The task warns about any it
  can't read; those have to be re-entered.
- Set `SITE_KEY` to the old subdomain and keep `<sub>.librepublish.com` as
  `APP_HOST` (the task prints both), so existing tokens, CLI profiles, Lumin
  and the Astro site keep working.
- Drain the old deployment's job queue before switching the hostname over.
