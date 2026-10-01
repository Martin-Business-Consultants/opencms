#!/bin/sh
# LibrePublish CMS — local agent setup.
#
#   curl -fsSL __CMS_URL__/agent/install.sh | sh
#
# Installs the `cms` CLI, connects this machine to __SITE__, and writes the
# two files an agent reads to know what it's working with: AGENTS.md in the
# current directory (Claude Code, opencode, Codex, …) and a Claude Code skill.
#
# Everything it writes:
#   ~/.local/bin/cms                    the CLI              (override: CMS_BIN_DIR)
#   ~/.config/cms/__SITE__.env        URL + token, 0600
#   ~/.config/cms/default               which profile is the default
#   ./AGENTS.md                         created, or appended to if it exists
#   ./.claude/skills/cms/SKILL.md       Claude Code skill    (skip: CMS_SKIP_SKILL=1)
#
# Connecting happens in your browser — nobody copies a token out of a settings
# page and pastes it into a terminal, which is how tokens end up in shell
# history and chat logs. For CI, where there is no browser, pass a token
# instead: USER_AGENT_TOKEN=… sh install.sh
set -eu

CMS_URL="${CMS_URL:-__CMS_URL__}"
CMS_URL="${CMS_URL%/}"
SITE="__SITE__"

BIN_DIR="${CMS_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cms"
PROFILE="${CMS_PROFILE:-$SITE}"
PROFILE_FILE="$CONFIG_DIR/$PROFILE.env"
MARKER="librepublish:cms-agent"

say()  { printf '%s\n' "$*"; }
step() { printf '\n▸ %s\n' "$*"; }
die()  { printf '\ninstall: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"

# The CLI is Ruby now — one file, stdlib only, no gems to install. Every macOS
# ships with a usable ruby; most Linux boxes need one line.
command -v ruby >/dev/null 2>&1 || die "ruby is required (the cms CLI is a single stdlib-only Ruby file).
  Debian/Ubuntu:  sudo apt install -y ruby
  Fedora:         sudo dnf install -y ruby
  macOS:          already installed"

say "LibrePublish CMS — agent setup"
say "  site:   $SITE"
say "  url:    $CMS_URL"

# ── 1. CLI ──────────────────────────────────────────────────────────────────
step "CLI"
mkdir -p "$BIN_DIR"
curl -fsSL "$CMS_URL/agent/cms" -o "$BIN_DIR/cms" || die "couldn't download the cms CLI"
chmod +x "$BIN_DIR/cms"
say "  ✓ $BIN_DIR/cms"

CMS="$BIN_DIR/cms"

# ── 2. Connect ──────────────────────────────────────────────────────────────
step "Connect"
mkdir -p "$CONFIG_DIR"

token="${USER_AGENT_TOKEN:-${CMS_TOKEN:-}}"
if [ -n "$token" ]; then
  # A token supplied up front: CI, or a re-run of a machine that already has
  # one. Verify it rather than writing a credential that turns out to be dead.
  whoami_json="$(curl -sS -H "Authorization: Bearer $token" -H "Accept: application/json" \
    "$CMS_URL/api/api_tokens/me")" || die "couldn't reach $CMS_URL"
  case "$whoami_json" in
    *'"token"'*) ;;
    *'"unauthorized"'*) die "that token was rejected. Rotating in Settings → API token issues a new one." ;;
    *) die "unexpected response from $CMS_URL/api/api_tokens/me: $whoami_json" ;;
  esac

  umask 077
  cat > "$PROFILE_FILE" <<EOF
# LibrePublish CMS — written by the agent installer. Keep this file private.
export CMS_URL="$CMS_URL"
export USER_AGENT_TOKEN="$token"
EOF
  chmod 600 "$PROFILE_FILE"
  [ -f "$CONFIG_DIR/default" ] || printf '%s\n' "$PROFILE" > "$CONFIG_DIR/default"
  say "  ✓ $PROFILE_FILE (0600)"
elif [ -r /dev/tty ]; then
  # Piped into sh, stdin is the script itself — give the CLI the terminal.
  "$CMS" login --url "$CMS_URL" --profile "$PROFILE" < /dev/tty || die "connecting failed"
else
  die "no terminal to approve in, and no token to fall back on. Either run this
  from a terminal, or pass a token:
    USER_AGENT_TOKEN=mbc_… sh -c \"\$(curl -fsSL $CMS_URL/agent/install.sh)\""
fi

# ── 3. Check ────────────────────────────────────────────────────────────────
# Answers the question the rest of the setup can't: whether this machine can
# actually do work, or is merely configured.
step "Check"
CMS_PROFILE="$PROFILE" "$CMS" doctor || die "connected, but not ready — see above"

# ── 4. AGENTS.md ────────────────────────────────────────────────────────────
step "AGENTS.md"
agents_md="$(curl -fsSL "$CMS_URL/agent/AGENTS.md")" || die "couldn't download AGENTS.md"
if [ ! -f AGENTS.md ]; then
  printf '%s\n' "$agents_md" > AGENTS.md
  say "  ✓ wrote ./AGENTS.md"
elif grep -q "$MARKER" AGENTS.md 2>/dev/null; then
  say "  · ./AGENTS.md already carries the CMS section — left alone"
  say "    (delete the '$MARKER' block and re-run to refresh it)"
else
  printf '\n' >> AGENTS.md
  printf '%s\n' "$agents_md" >> AGENTS.md
  say "  ✓ appended the CMS section to ./AGENTS.md"
fi
say "    ↳ it reads your Astro repo from the CMS (Settings → GitHub → Frontend repo)"

# ── 5. Claude Code skill ────────────────────────────────────────────────────
if [ "${CMS_SKIP_SKILL:-0}" != "1" ]; then
  step "Claude Code skill"
  mkdir -p .claude/skills/cms
  curl -fsSL "$CMS_URL/agent/SKILL.md" -o .claude/skills/cms/SKILL.md \
    || die "couldn't download SKILL.md"
  say "  ✓ ./.claude/skills/cms/SKILL.md"
  say "    (opencode and Codex read AGENTS.md directly — nothing else to do)"
fi

# ── 6. Done ─────────────────────────────────────────────────────────────────
step "Done"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    say "  ! $BIN_DIR isn't on your PATH. Add it:"
    say "      export PATH=\"\$PATH:$BIN_DIR\""
    ;;
esac
cat <<EOF

  cms doctor            can this machine do work, and what's stopping it
  cms manifest          the shape of this CMS — read this before writing
  cms commands --json   the whole surface at once, for an agent
  cms help              everything else

  Optional, for Claude Code — the same commands as MCP tools:
      claude mcp add cms -- $BIN_DIR/cms mcp

Then point your agent at this directory and tell it what to do. It reads
AGENTS.md, pulls your Astro repo from the CMS (asking you for it only if it
isn't recorded there yet), and works from there.
EOF
