#!/usr/bin/env bash
# Produce l'output reale del motore per ogni comando del contratto, con gli stub di tests/
# e una HOME temporanea, e lo scrive in <cartella>/<comando>.json (default:
# app/Tests/DevbarCoreTests/Fixtures/contract). Solo comandi di lettura sul Mac reale:
# tutto gira su PATH ristretto (stub + strumenti di sistema), HOME e cache temporanee.
# Le varianti di un comando hanno il nome <comando>.<variante>.json (stesso schema).
# Rigenerare con `just contract`.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO/app/Tests/DevbarCoreTests/Fixtures/contract}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/devbar-contract.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export BATS_TEST_TMPDIR="$TMP"
# shellcheck source=helpers.bash
source "$REPO/tests/helpers.bash"
setup_env
make_stub brew colima docker npm composer rtk tokensave claude-usage osascript

# PATH ristretto: stub, jq, git e strumenti di sistema. Nessun harness o tool reale visibile.
mkdir -p "$TMP/bin"
ln -sf "$(command -v jq)" "$TMP/bin/jq"
ln -sf "$(command -v git)" "$TMP/bin/git"
export PATH="$TMP/stubs:$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin"

DEVBAR="$REPO/bin/devbar"
HOMEDIR="$HOME"
ROOT="$HOME/repos"

# Repo finti: web (npm, con .tokensave), api (composer).
mkdir -p "$ROOT/web/.tokensave" "$ROOT/api"
: >"$ROOT/web/package-lock.json"
: >"$ROOT/api/composer.lock"
write_config "{\"repoRoots\":[\"$ROOT\"],\"scanDepth\":4,\"harnesses\":[]}"

# Plugin caveman installato e abilitato, modalità ultracave.
mkdir -p "$HOME/.config/caveman" "$HOME/.claude/plugins/cache/caveman/caveman/4.10.0"
echo '{"defaultMode":"ultracave"}' >"$HOME/.config/caveman/config.json"
echo '{"enabledPlugins":{"caveman@caveman":true}}' >"$HOME/.claude/settings.json"
mkdir -p "$TMP/Applications/Cork.app"
export DEVBAR_APPLICATIONS_DIR="$TMP/Applications"

# Anonimizza: percorsi temporanei -> /Users/example e /tmp/devbar-contract; data fissa.
# Rifiuta l'output se contiene ancora il nome utente reale.
normalize() {
  local f="$1" p
  for p in "/private$HOMEDIR" "$HOMEDIR"; do
    sed -i '' "s#$p#/Users/example#g" "$f"
  done
  for p in "/private$TMP" "$TMP"; do
    sed -i '' "s#$p#/tmp/devbar-contract#g" "$f"
  done
  jq 'walk(if type == "object" and has("checkedAt") then .checkedAt = "2026-01-01T00:00:00Z" else . end)' "$f" >"$f.n"
  mv "$f.n" "$f"
  if grep -qiE "$(id -un)|$TMP" "$f"; then
    echo "contract-fixtures: dati locali in $f" >&2
    exit 1
  fi
}

# fixture <nome> <comando devbar...>: l'rc del comando non conta, il JSON sì.
fixture() {
  local name="$1" f
  shift
  f="$OUT/$name.json"
  "$DEVBAR" "$@" >"$f" 2>/dev/null || true
  if ! jq -e . "$f" >/dev/null 2>&1; then
    echo "contract-fixtures: output non JSON per $name" >&2
    exit 1
  fi
  normalize "$f"
}

# Una sola scelta di stub per tutti i check (anche dentro `check all`).
export STUB_BREW_OUTDATED_FIXTURE=outdated.json STUB_BREW_VULNS_FIXTURE=vulns-two.json
export STUB_NPM_FIXTURE=audit-critical.json STUB_COMPOSER_FIXTURE=audit-high.json
export STUB_COLIMA_FIXTURE=list-running.json STUB_DOCKER_FIXTURE=stats-two.json
export STUB_RTK_GAIN_FIXTURE=gain-10days.json
export STUB_TOKENSAVE_GAIN_FIXTURE=gain.json STUB_TOKENSAVE_DISCOVER_FIXTURE=discover-empty.json
export STUB_CLAUDE_USAGE_FIXTURE=status.json

fixture brew-outdated check brew-outdated
fixture brew-vulns check brew-vulns
fixture npm-audit check npm-audit
fixture composer-audit check composer-audit
fixture colima check colima
fixture rtk check rtk
fixture tokensave check tokensave
fixture caveman check caveman
fixture claude-usage check claude-usage
fixture harnesses check harnesses
fixture all check all
fixture detect detect
fixture repos repos
fixture check-timeouts check-timeouts

# Varianti: audit con un repo in errore (output non valido), usage senza credenziali.
(
  export STUB_NPM_FIXTURE=../claude-usage/broken.txt DEVBAR_CACHE_DIR="$TMP/cache-err"
  fixture npm-audit.error check npm-audit
)
(
  export STUB_CLAUDE_USAGE_FIXTURE=status-missing.json
  fixture claude-usage.missing check claude-usage
)

# ai-status e project-status: tool installato, stato da `rtk init --show`.
(
  export STUB_RTK_FIXTURE=show-all.txt
  fixture ai-status run ai-status rtk
  fixture plan run ai-install rtk claude
)
REPO_P="$ROOT/proj"
mkdir -p "$REPO_P"
git -C "$REPO_P" init -q
fixture project-status run project-status "$REPO_P"

# Azioni che scrivono (solo su HOME e config temporanei, separati da quelli dei check).
(
  export HOME="$TMP/home2" DEVBAR_CONFIG="$TMP/config2.json"
  mkdir -p "$HOME"
  fixture caveman-mode.plan run caveman-mode megacave
  fixture caveman-mode run caveman-mode megacave --yes
  fixture tool-install run tool-install claude-usage --yes
)
