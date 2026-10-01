# The agent interface

Three things sit between an agent and this CMS: the **CLI** (`agent/cms`), the
**envelope** it can ask the API for, and the **device login** that gets a
credential onto a machine without anyone pasting a token. This is why each of
them is shaped the way it is.

The short version: an agent working through an API spends most of its budget
finding out what it is allowed to do, what it just got back, and what to do
next. Every design decision below is aimed at one of those three.

## The CLI is Ruby, and it is one file

It was `sh` until now. Ruby buys three things that mattered more than the
dependency: real JSON handling (no `jq`, no hand-rolled escaping that breaks on
an apostrophe), one catalogue that both the dispatcher and `cms commands --json`
read, and a `login` that can poll.

Still stdlib only, still a single file, still served from `/agent/cms` and
downloaded by `curl`. The installer now checks for `ruby` and says how to get it.

## The catalogue is the surface

`COMMANDS` is a table of every command with its summary, usage, flags, notes and
suggested next steps. The dispatcher runs from it and `cms commands --json`
prints it.

That coupling is the point. A surface described in a comment drifts from the
surface that runs, and an agent reading the drifted one wastes a call finding
out. Here, a command that isn't in the table can't be dispatched, and a command
in the table always has a usage line — `spec/cli/cms_cli_spec.rb` asserts both.

`notes:` is where the traps go. `cms work` exits **3** when the queue is empty so
a polling loop can tell "idle" from "broken"; `cms schema` **replaces** a field
list rather than merging it; `cms publish` needs `pages:publish` and a role with
only `pages:write` will be refused. None of those are discoverable from a 200.

## The envelope is opt-in

With `X-Agent-Envelope: 1` (or `?envelope=1`), a response becomes:

```json
{"status": "ok", "summary": "…", "data": {…}, "breadcrumbs": [{"description": "…", "command": "…"}]}
```

Without it, every endpoint returns exactly what it always did. That is what made
this safe to add: the SSR build, the webhook consumers and every installed copy
of the old CLI keep working untouched. The CLI asks for it on `--agent`,
`--json`, and always over MCP.

`summary` is the one line a person would say out loud. `breadcrumbs` are the
next commands — **filled in with the ids and paths just returned**, not
templates. `cms work` comes back with `cms run-start 41`, not
`cms run-start <id>`. A breadcrumb the agent has to substitute into is a
breadcrumb it can get wrong, and the whole value is that the surface teaches
itself as it is used.

Controllers declare what they have to say:

```ruby
agent_summary(:index) { |payload| "#{payload["total"]} pages." }
agent_breadcrumbs(:index) do |payload|
  [crumb("Open one", "cms page #{payload.dig("pages", 0, "path")}")]
end
```

Anything undeclared gets a default derived from the payload — it counts the
first array it finds and names it.

**A declaration that raises must not take the payload with it.** Both hooks are
rescued and logged. This is not hypothetical: a summary block that assumed
`agent` was an object when the serializer rendered it as a string turned a
working `cms work` into a 500. The envelope is decoration on a response that has
already succeeded, and it is never worth the response.

## `cms doctor`

The hardest question to ask over an API is "can this machine actually do work?"
A 200 from one endpoint doesn't answer it.

`doctor` checks the profile, the credential, that the site answers, who the
token is, what the role grants, whether anything is queued, and whether a
harness is on PATH. It exits non-zero when something is broken, so provisioning
can gate on it.

The check that earns its place is **`agents:run`**. A token whose role lacks it
polls forever and is handed nothing — which looks exactly like an idle queue.
Without doctor, that failure is invisible for as long as nobody thinks to look.

Doctor's own probes ask for the *bare* response (`envelope: false`). They read
the payload rather than printing it, and reading capabilities off the wrapper is
how `cms doctor --agent` once reported a healthy machine as broken.

## Device login

`cms login` mints a code pair, shows the short one, and polls while the person
approves it in a browser they are already signed into. The next poll returns the
token and destroys the handshake.

Nobody copies a token out of a settings page and pastes it into a terminal —
which is how tokens end up in shell history, in a screen share, and in a chat
log. The browser proves who they are; typing the code proves they are at the
machine that asked. The machine cannot approve itself.

Details that matter:

- The `device_code` is one-shot. A copy that leaks after the handshake is
  worthless, because the handshake no longer exists.
- Unknown and expired codes answer identically (410). Distinguishing them turns
  the endpoint into an oracle for guessing device codes.
- Codes are 8 characters from an alphabet with no `0/O` or `1/I/L`, and are
  matched case- and dash-insensitively — they get retyped by hand.
- Fifteen-minute TTL, IP rate limit on minting.

`--profile` names an identity that may not exist yet, so resolving it must not
fail: `cms login --profile acme` is precisely how `acme` comes to exist. The
complaint about a missing profile belongs at the point of use.

## Profiles

`~/.config/cms/<name>.env`, mode 0600, plus a `default` file naming one. One
machine can hold several — a person and a service account, or two sites.
Resolution order: `--profile`, `CMS_PROFILE`, `CMS_URL`/`USER_AGENT_TOKEN` from
the environment, then the default. The old single-file `~/.config/cms/config` is
still read as the profile named `default`, so existing installs keep working.

Login saves **the URL that just worked from this machine**, not the one the
server believes it lives at. Behind a tunnel, a port-forward or a dev proxy
those differ, and only one of them is reachable from here.

## MCP

`cms mcp` speaks JSON-RPC on stdio and exposes every catalogue command as a
tool, so `claude mcp add cms -- cms mcp` is the whole setup. It shares the
catalogue with the CLI, so the two cannot drift.

Tool calls always get the envelope and always capture **both** streams: an MCP
client has no terminal and no stderr, so an error written to stderr would reach
it as silence. A failed call must come back saying what went wrong.

## What is deliberately absent

There is no curated command for every write. Creating a page goes through
`cms post /pages '…'`. Adding one shortcut per endpoint would double the surface
an agent has to read for no new capability — `cms manifest` already says what
the payload must look like, and the escape hatch reaches everything.

The CLI does not validate payloads locally. The server owns what is valid, and a
second copy of those rules on every machine is a second copy to be wrong. The
job here is to make the server's refusal legible: a 422 now names the allowed
values instead of saying "is not included in the list".

## The admin points here

The admin is WordPress-shaped on purpose, for people doing things by hand; the
CLI, its MCP server and the API are the surface the CMS is built around. So
the admin says so: every screen that has a `cms` command names it under its
title (`HeadlessHelper#cli_command_hint`), every page, entry and global has a
JSON tab showing what the API returns for it, and Developers leads with the
three surfaces. A new admin screen should come with its command, or a reason
it has none.

## Sites connect the same way people do

`/frontend/install.sh`, run in an Astro project, asks for a token through the
same device login as `cms login`, with `purpose=site`: approving it (which
takes `settings:write`) issues the site a read-only service token on the
Production site role instead of handing over the approver's own. The site
then builds with the `cms()` integration (integrations/astro), which writes
the frontend AGENTS.md into its repo and reports each build
(`GET /api/frontend`, `cms frontend`).

