#!/bin/sh
# LibrePublish CMS — connect an Astro site to __SITE__.
#
#   curl -fsSL __CMS_URL__/frontend/install.sh | sh
#
# Run it in an Astro project (its root, or its src/ directory). It:
#
#   src/lib/cms/*.ts                    the client, types, block helpers and the cms() integration
#   src/pages/emails/[form]/[kind].astro  the form email route, unless there's one already
#   astro.config.*                      imports cms() and adds it to integrations
#   .env                                CMS_BASE_URL and CMS_API_TOKEN (kept out of git)
#
# The token is the site's own read-only service token, approved in your
# browser — nobody copies one out of a settings page. For CI, pass one
# instead: CMS_API_TOKEN=mbc_… sh -c "$(curl -fsSL __CMS_URL__/frontend/install.sh)"
#
# Then `npx astro dev` writes AGENTS.md (how this site works with the CMS)
# and .cms/manifest.json (the content model). Re-running refreshes the files
# and leaves everything else alone.
set -eu

CMS_URL="${CMS_URL:-__CMS_URL__}"
CMS_URL="${CMS_URL%/}"
SITE="__SITE__"

say()  { printf '%s\n' "$*"; }
step() { printf '\n▸ %s\n' "$*"; }
die()  { printf '\ninstall: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v node >/dev/null 2>&1 || die "node is required (an Astro project has it)"

# ── 1. Find the project ─────────────────────────────────────────────────────
# The directory with astro.config.*: here, or up to three levels above (so
# running it from src/ works).
find_root() {
  dir="$PWD"
  for _ in 1 2 3 4; do
    for ext in mjs ts mts js cjs; do
      if [ -f "$dir/astro.config.$ext" ]; then ROOT="$dir"; CONFIG="$dir/astro.config.$ext"; return 0; fi
    done
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  return 1
}
find_root || die "no astro.config.* here or above — run this inside an Astro project"
NAME="$(node -e 'try{console.log(require(process.argv[1]).name||"")}catch{console.log("")}' "$ROOT/package.json")"
NAME="${NAME:-$(basename "$ROOT")}"

say "LibrePublish CMS — connect an Astro site"
say "  cms:     $CMS_URL ($SITE)"
say "  project: $ROOT"

# ── 2. Files ────────────────────────────────────────────────────────────────
step "Integration files"
mkdir -p "$ROOT/src/lib/cms"
for file in cms types blocks sitemap emails integration webhook-handler; do
  curl -fsSL "$CMS_URL/frontend/files/$file.ts" -o "$ROOT/src/lib/cms/$file.ts" || die "couldn't download $file.ts"
done
say "  ✓ src/lib/cms/ (cms, types, blocks, sitemap, emails, integration, webhook-handler)"

route="$ROOT/src/pages/emails/[form]/[kind].astro"
if [ -f "$route" ]; then
  say "  · src/pages/emails/[form]/[kind].astro is yours already — left alone"
else
  mkdir -p "$ROOT/src/pages/emails/[form]"
  curl -fsSL "$CMS_URL/frontend/files/email-route.astro" -o "$route" || die "couldn't download the email route"
  say "  ✓ src/pages/emails/[form]/[kind].astro (the form emails' design — make it yours)"
fi

# ── 3. astro.config ─────────────────────────────────────────────────────────
step "astro.config"
node - "$CONFIG" <<'JS'
const fs = require("fs");
const file = process.argv[2];
let src = fs.readFileSync(file, "utf8");
if (/\bcms\(\s*[^)]*\)/.test(src) && src.includes("lib/cms/integration")) {
  console.log("  · already has cms() — left alone");
  process.exit(0);
}
const importLine = 'import { cms } from "./src/lib/cms/integration";';
const imports = [...src.matchAll(/^import[^\n]*\n/gm)];
src = imports.length
  ? src.slice(0, imports.at(-1).index + imports.at(-1)[0].length) + importLine + "\n" + src.slice(imports.at(-1).index + imports.at(-1)[0].length)
  : importLine + "\n" + src;
if (/integrations\s*:\s*\[/.test(src)) {
  src = src.replace(/integrations\s*:\s*\[/, (m) => m + "cms(), ");
} else if (/defineConfig\(\s*\{/.test(src)) {
  src = src.replace(/defineConfig\(\s*\{/, (m) => m + "\n  integrations: [cms()],");
} else {
  console.log("  ! couldn't find where to add it. Add cms() to integrations in " + file + " yourself:");
  console.log("      " + importLine);
  console.log("      export default defineConfig({ integrations: [cms()] });");
  process.exit(0);
}
fs.writeFileSync(file, src);
console.log("  ✓ " + require("path").basename(file) + ": cms() added to integrations");
JS

# ── 4. Connect ──────────────────────────────────────────────────────────────
step "Connect"
json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const v=JSON.parse(s)[process.argv[1]];console.log(v??"")}catch{console.log("")}})' "$1"; }

token="${CMS_API_TOKEN:-}"
if [ -z "$token" ] && [ -f "$ROOT/.env" ]; then
  token="$(sed -n 's/^CMS_API_TOKEN=//p' "$ROOT/.env" | tail -1)"
fi

if [ -n "$token" ]; then
  say "  · using the token already given"
elif [ -r /dev/tty ]; then
  code_json="$(curl -fsS -X POST "$CMS_URL/api/device/code" \
    --data-urlencode "purpose=site" --data-urlencode "label=$NAME" --data-urlencode "hostname=$(hostname 2>/dev/null || echo site)")" \
    || die "couldn't reach $CMS_URL"
  device_code="$(printf '%s' "$code_json" | json device_code)"
  user_code="$(printf '%s' "$code_json" | json user_code)"
  url="$(printf '%s' "$code_json" | json verification_url)"
  interval="$(printf '%s' "$code_json" | json interval)"
  [ -n "$device_code" ] || die "unexpected response from the CMS: $code_json"

  say "  Approve this site in your browser (signed in to the CMS):"
  say "      $url"
  say "  and check it shows the code  $user_code"
  (command -v open >/dev/null 2>&1 && open "$url") || (command -v xdg-open >/dev/null 2>&1 && xdg-open "$url") || true

  tries=0
  while :; do
    sleep "${interval:-3}"
    tries=$((tries + 1))
    [ "$tries" -gt 300 ] && die "gave up waiting for approval"
    status="$(curl -sS -o /tmp/cms-device-$$ -w '%{http_code}' -X POST "$CMS_URL/api/device/token" --data-urlencode "device_code=$device_code")"
    case "$status" in
      202) ;;
      200) token="$(json token < /tmp/cms-device-$$)"; rm -f /tmp/cms-device-$$; break ;;
      403) rm -f /tmp/cms-device-$$; die "approval was denied" ;;
      *) rm -f /tmp/cms-device-$$; die "the code expired — run this again" ;;
    esac
  done
  say "  ✓ approved: the site has a read-only service token of its own"
else
  die "no terminal to approve in, and no token. Pass one:
    CMS_API_TOKEN=mbc_… sh -c \"\$(curl -fsSL $CMS_URL/frontend/install.sh)\""
fi

check="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" "$CMS_URL/api/manifest")"
[ "$check" = "200" ] || die "the CMS refused that token ($check)"

env_file="$ROOT/.env"
touch "$env_file"
grep -v '^CMS_BASE_URL=\|^CMS_API_TOKEN=' "$env_file" > "$env_file.tmp" || true
{ cat "$env_file.tmp"; printf 'CMS_BASE_URL=%s\nCMS_API_TOKEN=%s\n' "$CMS_URL" "$token"; } > "$env_file"
rm -f "$env_file.tmp"
chmod 600 "$env_file"
if [ ! -f "$ROOT/.gitignore" ] || ! grep -qx '.env' "$ROOT/.gitignore"; then
  printf '.env\n' >> "$ROOT/.gitignore"
fi
say "  ✓ .env (CMS_BASE_URL, CMS_API_TOKEN) — kept out of git"

# ── 5. Done ─────────────────────────────────────────────────────────────────
step "Done"
cat <<EOF
  Set the same two variables where the site builds (your host, or the
  repo's secrets for .github/workflows/cms-publish.yml).

  npx astro dev     writes AGENTS.md (how this site works with the CMS) and
                    .cms/manifest.json (its content model) — commit both
  npx astro build   also sends the form email templates, and reports the
                    build to the CMS (Developers, in its admin)

  Then fetch content with the client:
      import { cms } from "./src/lib/cms/cms";
      const page = await cms.pages.get("home");
EOF
