# How agents are built here

Three layers, and the reason for each is that the layer above it kept being
edited by hand until it drifted.

```
config/agents/*.yml        the library    what an agent IS, versioned, in git
agents (table)             an instance    the library pinned to a version, plus
                                          this site's scope and cadence
swarms / swarm_members     a rota         several instances on different rhythms
```

## The library

`config/agents/*.yml` — one file per template, the file name IS the key. Each
declares its instructions, the capabilities it may use, a model **tier**, a
budget, and a cron.

It is YAML in git rather than rows in a table because a prompt is source code.
It reviews in a pull request, it bisects, and a bad version rolls back by
reverting a commit instead of by remembering what the textarea used to say.

`spec/services/agents/library_spec.rb` checks every claim a template makes on
every commit: the capabilities exist in the catalogue, the budget is inside
`Agents::Budget::CEILING`, the tier resolves to a model we actually ship, the
cron parses, and the file name matches the key. These are the mistakes people
really make — a capability renamed in the catalogue and not in the four
templates that grant it, a cron typo that silently means "never" — and each is
quiet at runtime and loud here.

## Instances

An `Agent` row is a template stood up for this workspace: the shipped fields,
plus the scope and cadence that are genuinely local, plus a
`template_version` stamp.

The stamp is what makes an upgrade a decision instead of a surprise.
`Agent#upgradable?` says a newer version exists; `#library_changes` says what
taking it would replace, field by field, in the same words the form uses. A
site may have edited any of those fields, so "a newer version exists" and
"your instructions will be replaced" are different sentences and the agents
page shows both before the button.

`POST /agents/:id/upgrade` applies it and re-stamps.

## Tiers, not model ids

An agent asks for `cheap`, `mid` or `strong`. `Ai::Models` resolves that to an
id at dispatch and stamps the id into the run's brief.

The tier is the decision — "this job deserves the strong model" — and it
survives the provider changing underneath it. A seat that named a raw id went
on naming it after the id stopped existing: configured-looking, and resolving
to nothing.

Because the id is stamped per run, cost is always priced at what was actually
used. An agent moved from cheap to strong last Tuesday did not retroactively
make last Monday's run expensive.

## Budgets

`Agents::Budget` — `tool_rounds`, `proposals`, `context_tokens`, each clamped
to a ceiling. Stated in the brief for the harness to honour; the CMS does not
execute runs, so it is a limit it *declares*, not one it enforces.

Worth declaring anyway. An agent asked for "your top findings" with no ceiling
returns an essay; one told "at most eight fixes, ten rounds to find them"
returns eight fixes.

## Swarms

A swarm's failure mode is not one agent doing its job badly. It is five agents
each doing their job well and filing the same finding five times, until the
queue stops being read.

`Agents::SwarmBrief` puts two facts in front of every seat before it starts:

- **already filed** — what other seats have put in the queue this cycle.
- **settled** — what this swarm has recommended before and a person dismissed,
  with the reason. Re-filing a dismissed finding tells the reader their
  decision didn't take.

A *cycle* is the current pass of the rota, derived from the slowest enabled
seat. Nothing to migrate, and it stays right when a seat's cadence changes.

`Agents::CycleSynthesis` then judges the cycle as a **set**: how many findings,
across how many distinct subjects, how many were the same work seen by two
seats, and what it cost. Deliberately arithmetic rather than a model call — a
synthesis that can itself be wrong is a worse thing to put in front of someone
than a count they can check.

## What it costs

`Agents::Scorecard` reports per agent and per template. The number that decides
whether an agent earns its place is **cost per accepted recommendation** —
acceptance rate alone flatters an agent that files one safe finding a month,
and cost alone says nothing about value.

It is `nil`, never zero, until something has been accepted: "nothing good has
landed yet" is not "each one was free".

## Evals

`config/agents/evals/*.yml`, one scenario per file, each naming a template and
what it must (and must not) recommend.

The `never` half is the one that earns its keep. An agent wandering outside its
brief — a metadata pass that starts restructuring the site — has not failed
loudly; it has done something plausible and wrong, which a per-item reviewer
waves through.

`Agents::TemplateEval#errors` runs free in CI and catches evals that drift from
the templates they name. `#score` is pure, so the rules are testable without a
model.

## The AI key

`Settings → AI` holds an OpenCode Zen credential in `Setting`'s encrypted
`secrets` column, and a default tier.

**Agent runs do not use it.** Those execute on a worker box holding its own
credential. This key is for the short, tool-less calls the CMS makes itself and
waits on — drafting an agent's instructions, summarising a cycle. Without it
those helpers are simply absent; nothing else stops working.
