#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Formati reali: ogni check gira sulla fixture registrata più recente di ogni strumento
# (tests/fixtures/real, prodotta da scripts/record-fixtures.sh) e l'uscita deve rispettare lo
# schema in schemas/. Se lo strumento cambia formato, il check deve dire "formato di <strumento>
# non riconosciuto (versione X)" con rc 2: mai un 0 che sembra un risultato.
# Richiede check-jsonschema (brew install check-jsonschema).

load helpers

setup() {
  setup_env
  make_stub brew rtk tokensave colima docker npm composer claude-usage claude
  DEVBAR="$DEVBAR_REPO/bin/devbar"
  # versioni lette dal check solo nel caso di formato non riconosciuto
  export STUB_BREW___VERSION_FIXTURE=../versions/brew.txt
  export STUB_RTK___VERSION_FIXTURE=../versions/rtk.txt
  export STUB_TOKENSAVE___VERSION_FIXTURE=../versions/tokensave.txt
  export STUB_COLIMA_VERSION_FIXTURE=../versions/colima.txt
  export STUB_NPM__V_FIXTURE=../versions/npm.txt
  export STUB_COMPOSER___VERSION_FIXTURE=../versions/composer.txt
  export STUB_CLAUDE_USAGE___VERSION_FIXTURE=../versions/claude-usage.txt
}

# latest <nome>: fixture reale più recente (relativa a tests/fixtures, per gli stub).
latest() {
  local f
  f="$(ls "$DEVBAR_REPO"/tests/fixtures/real/"$1"-[0-9]*.* 2>/dev/null | sort -V | tail -n 1)"
  [ -n "$f" ] || return 1
  printf '../real/%s' "$(basename "$f")"
}

# unrecognized <strumento> <schema>: errore di formato con la versione, valido per lo schema del check.
unrecognized() {
  [ "$status" -eq 2 ]
  schema_ok "$2" "$output"
  [ "$(jq -r .status <<<"$output")" = error ]
  [[ "$(jq -r .summary <<<"$output")" =~ ^formato\ di\ "$1"\ non\ riconosciuto\ \(versione\ [0-9.]+\)$ ]] ||
    { echo "summary: $(jq -r .summary <<<"$output")" >&2; return 1; }
}

@test "reale: brew-outdated" {
  export STUB_BREW_OUTDATED_FIXTURE="$(latest brew-outdated)"
  run --separate-stderr "$DEVBAR" check brew-outdated
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" -ge 1 ]
  schema_ok brew-outdated "$output"
}

@test "reale: brew-vulns" {
  export STUB_BREW_VULNS_FIXTURE="$(latest brew-vulns)"
  run --separate-stderr "$DEVBAR" check brew-vulns --force
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" -ge 1 ]
  schema_ok brew-vulns "$output"
}

@test "reale: rtk" {
  export STUB_RTK_FIXTURE="$(latest rtk-gain)"
  run --separate-stderr "$DEVBAR" check rtk
  [ "$status" -eq 1 ]
  [ "$(jq -r '.saved > 0' <<<"$output")" = true ]
  [ "$(jq -r '.daily | length' <<<"$output")" = 7 ]
  schema_ok rtk "$output"
}

@test "reale: tokensave" {
  export STUB_TOKENSAVE_GAIN_FIXTURE="$(latest tokensave-gain)"
  export STUB_TOKENSAVE_DISCOVER_FIXTURE="$(latest tokensave-discover)"
  run --separate-stderr "$DEVBAR" check tokensave
  [ "$status" -eq 1 ]
  [ "$(jq -r '.missedTurns > 0' <<<"$output")" = true ]
  schema_ok tokensave "$output"
}

@test "reale: colima" {
  export STUB_COLIMA_LIST_FIXTURE="$(latest colima-list)"
  export STUB_DOCKER_RC=1
  run --separate-stderr "$DEVBAR" check colima
  [ "$status" -eq 1 ]
  [ "$(jq -r '.profiles | length' <<<"$output")" -ge 1 ]
  [ "$(jq -r '.profiles[0].name' <<<"$output")" = default ]
  schema_ok colima "$output"
}

@test "reale: npm-audit sul repo di esempio" {
  local R="$BATS_TEST_TMPDIR/root"
  mkdir -p "$R/sample"
  cp "$DEVBAR_REPO/tests/fixtures/sample-repo/package-lock.json" "$R/sample/"
  write_config "{\"repoRoots\":[\"$R\"],\"scanDepth\":4}"
  export STUB_NPM_AUDIT_FIXTURE="$(latest npm-audit)" STUB_NPM_RC=1
  run --separate-stderr "$DEVBAR" check npm-audit --force
  [ "$status" -eq 0 ]
  [ "$(jq -r '.items[0].critical + .items[0].high + .items[0].moderate + .items[0].low' <<<"$output")" -ge 1 ]
  schema_ok npm-audit "$output"
}

@test "reale: composer-audit (nessuna fixture: composer non è installato qui)" {
  latest composer-audit >/dev/null || skip "composer assente su questo Mac: nessuna fixture reale"
}

@test "reale: claude-usage (nessuna fixture: claude-usage non è installato qui)" {
  latest claude-usage-status >/dev/null || skip "claude-usage assente su questo Mac: nessuna fixture reale"
}

@test "reale: docker stats (nessuna fixture: docker non raggiungibile qui)" {
  latest docker-stats >/dev/null || skip "docker non raggiungibile su questo Mac: nessuna fixture reale"
}

# --- formato non riconosciuto: rc 2, mai un 0 ---------------------------------------------

@test "brew-outdated: JSON di altra forma -> formato non riconosciuto" {
  export STUB_BREW_OUTDATED_FIXTURE=../wrong/object.json
  run --separate-stderr "$DEVBAR" check brew-outdated
  unrecognized brew brew-outdated
}

@test "brew-outdated: testo non JSON -> formato non riconosciuto" {
  export STUB_BREW_OUTDATED_FIXTURE=outdated-broken.txt
  run --separate-stderr "$DEVBAR" check brew-outdated
  unrecognized brew brew-outdated
}

@test "brew-vulns: JSON di altra forma -> formato non riconosciuto" {
  export STUB_BREW_VULNS_FIXTURE=../wrong/object.json
  run --separate-stderr "$DEVBAR" check brew-vulns --force
  unrecognized brew brew-vulns
}

@test "brew-vulns: findings senza formula -> formato non riconosciuto" {
  export STUB_BREW_VULNS_FIXTURE=vulns-badshape.json
  run --separate-stderr "$DEVBAR" check brew-vulns --force
  unrecognized brew brew-vulns
}

@test "rtk: summary vuoto -> formato non riconosciuto" {
  export STUB_RTK_FIXTURE=../wrong/summary-empty.json
  run --separate-stderr "$DEVBAR" check rtk
  unrecognized rtk rtk
}

@test "rtk: testo non JSON -> formato non riconosciuto" {
  export STUB_RTK_FIXTURE=gain-broken.txt
  run --separate-stderr "$DEVBAR" check rtk
  unrecognized rtk rtk
}

@test "tokensave: gain di altra forma -> formato non riconosciuto" {
  export STUB_TOKENSAVE_GAIN_FIXTURE=../wrong/object.json STUB_TOKENSAVE_DISCOVER_FIXTURE=discover-empty.json
  run --separate-stderr "$DEVBAR" check tokensave
  unrecognized tokensave tokensave
}

@test "tokensave: discover di altra forma -> formato non riconosciuto" {
  export STUB_TOKENSAVE_GAIN_FIXTURE=gain.json STUB_TOKENSAVE_DISCOVER_FIXTURE=../wrong/object.json
  run --separate-stderr "$DEVBAR" check tokensave
  unrecognized tokensave tokensave
}

@test "colima: righe JSON senza nome -> formato non riconosciuto" {
  export STUB_COLIMA_LIST_FIXTURE=../wrong/array-of-objects.json
  run --separate-stderr "$DEVBAR" check colima
  unrecognized colima colima
}

@test "colima: testo non JSON -> formato non riconosciuto" {
  export STUB_COLIMA_LIST_FIXTURE=../rtk/gain-broken.txt
  run --separate-stderr "$DEVBAR" check colima
  unrecognized colima colima
}

@test "colima: nessun output = nessun profilo (non è un errore)" {
  export STUB_COLIMA_LIST_FIXTURE=
  run --separate-stderr "$DEVBAR" check colima
  [ "$status" -eq 1 ]
  [ "$(jq -r .summary <<<"$output")" = "Colima spento" ]
}

# audit: un repo con package-lock/composer.lock, l'audit risponde in formato strano.
_audit_repo() {
  local R="$BATS_TEST_TMPDIR/root"
  mkdir -p "$R/r"
  : >"$R/r/$1"
  write_config "{\"repoRoots\":[\"$R\"],\"scanDepth\":4}"
}

@test "npm-audit: metadata senza conteggi -> formato non riconosciuto" {
  _audit_repo package-lock.json
  export STUB_NPM_AUDIT_FIXTURE=../wrong/npm-no-vulns.json STUB_NPM_RC=1
  run --separate-stderr "$DEVBAR" check npm-audit --force
  [ "$status" -eq 2 ]
  [[ "$(jq -r .summary <<<"$output")" == *"formato di npm non riconosciuto (versione 11.20.0)"* ]]
  schema_ok npm-audit "$output"
}

@test "composer-audit: advisories di altra forma -> formato non riconosciuto" {
  _audit_repo composer.lock
  export STUB_COMPOSER_AUDIT_FIXTURE=../wrong/composer-advisories.json STUB_COMPOSER_RC=1
  run --separate-stderr "$DEVBAR" check composer-audit --force
  [ "$status" -eq 2 ]
  [[ "$(jq -r .summary <<<"$output")" == *"formato di composer non riconosciuto (versione 2.8.4)"* ]]
  schema_ok composer-audit "$output"
}

@test "npm-audit: errore dichiarato da npm -> non riuscito con il messaggio, non formato" {
  _audit_repo package-lock.json
  export STUB_NPM_AUDIT_FIXTURE=../wrong/npm-error.json STUB_NPM_RC=1
  run --separate-stderr "$DEVBAR" check npm-audit --force
  [ "$status" -eq 2 ]
  [ "$(jq -r .summary <<<"$output")" = "npm audit non riuscito: request to https://registry.npmjs.org failed" ]
  schema_ok npm-audit "$output"
}

@test "npm-audit: \"error\":null con conteggi -> risultato normale" {
  _audit_repo package-lock.json
  export STUB_NPM_AUDIT_FIXTURE=../wrong/npm-error-null.json STUB_NPM_RC=1
  run --separate-stderr "$DEVBAR" check npm-audit --force
  [ "$status" -eq 0 ]
  [[ "$(jq -r .summary <<<"$output")" != *"non riuscito"* ]]
  [ "$(jq -r '.items[0].high' <<<"$output")" = 1 ]
}

@test "npm-audit: \"error\":null senza conteggi -> formato non riconosciuto, mai \"non riuscito: null\"" {
  _audit_repo package-lock.json
  export STUB_NPM_AUDIT_FIXTURE=../wrong/npm-error-null-nometa.json STUB_NPM_RC=1
  run --separate-stderr "$DEVBAR" check npm-audit --force
  [ "$status" -eq 2 ]
  [[ "$(jq -r .summary <<<"$output")" == *"formato di npm non riconosciuto"* ]]
  [[ "$(jq -r .summary <<<"$output")" != *"null"* ]]
  schema_ok npm-audit "$output"
}

@test "composer-audit: errore dichiarato -> non riuscito con il messaggio" {
  _audit_repo composer.lock
  export STUB_COMPOSER_AUDIT_FIXTURE=../wrong/composer-error.json STUB_COMPOSER_RC=1
  run --separate-stderr "$DEVBAR" check composer-audit --force
  [ "$status" -eq 2 ]
  [ "$(jq -r .summary <<<"$output")" = "composer audit non riuscito: Could not reach packagist" ]
  schema_ok composer-audit "$output"
}

@test "claude-usage: JSON di altra forma -> formato non riconosciuto" {
  export STUB_CLAUDE_USAGE_FIXTURE=../wrong/object.json
  run --separate-stderr "$DEVBAR" check claude-usage
  unrecognized claude-usage claude-usage
}

@test "la versione compare nel messaggio (brew 7.0.16)" {
  export STUB_BREW_OUTDATED_FIXTURE=../wrong/object.json
  run --separate-stderr "$DEVBAR" check brew-outdated
  [ "$(jq -r .summary <<<"$output")" = "formato di brew non riconosciuto (versione 7.0.16)" ]
}

@test "versione illeggibile -> sconosciuta" {
  export STUB_BREW_OUTDATED_FIXTURE=../wrong/object.json STUB_BREW___VERSION_FIXTURE=../wrong/object.json
  run --separate-stderr "$DEVBAR" check brew-outdated
  [ "$status" -eq 2 ]
  [ "$(jq -r .summary <<<"$output")" = "formato di brew non riconosciuto (versione sconosciuta)" ]
  schema_ok brew-outdated "$output"
}

# --- record-fixtures --------------------------------------------------------------------

_rec_setup() {
  make_stub brew rtk tokensave colima docker npm claude-usage composer
  FX="$BATS_TEST_TMPDIR/fx"
  mkdir -p "$FX/brew" "$FX/rtk" "$FX/tokensave" "$FX/colima" "$FX/docker" "$FX/npm" "$BATS_TEST_TMPDIR/sample"
  export STUB_FIXTURES_DIR="$FX"
  : >"$BATS_TEST_TMPDIR/sample/package-lock.json"
  printf 'Homebrew 7.0.16\n' >"$FX/brew/v.txt"
  printf '{"formulae":[],"casks":[]}\n' >"$FX/brew/o.json"
  printf '{"findings":[]}\n' >"$FX/brew/vu.json"
  printf 'rtk 1.2.1\n' >"$FX/rtk/v.txt"
  printf '{"summary":{"total_saved":1}}\n' >"$FX/rtk/g.json"
  printf 'tokensave 7.17.3\n' >"$FX/tokensave/v.txt"
  printf '{"saved_tokens":1,"calls":1}\n' >"$FX/tokensave/g.json"
  printf '{"replaceable_turns":1}\n' >"$FX/tokensave/d.json"
  printf 'colima version 0.10.3\n' >"$FX/colima/v.txt"
  printf '{"name":"default","status":"Running","dir":"%s/.colima"}\n' "$HOME" >"$FX/colima/l.json"
  printf '11.20.0\n' >"$FX/npm/v.txt"
  printf '{"metadata":{"vulnerabilities":{"low":0}}}\n' >"$FX/npm/a.json"
  export STUB_BREW___VERSION_FIXTURE=v.txt STUB_BREW_OUTDATED_FIXTURE=o.json STUB_BREW_VULNS_FIXTURE=vu.json
  export STUB_RTK___VERSION_FIXTURE=v.txt STUB_RTK_GAIN_FIXTURE=g.json
  export STUB_TOKENSAVE___VERSION_FIXTURE=v.txt STUB_TOKENSAVE_GAIN_FIXTURE=g.json STUB_TOKENSAVE_DISCOVER_FIXTURE=d.json
  export STUB_COLIMA_VERSION_FIXTURE=v.txt STUB_COLIMA_LIST_FIXTURE=l.json
  export STUB_NPM__V_FIXTURE=v.txt STUB_NPM_AUDIT_FIXTURE=a.json
  export STUB_DOCKER_RC=1
  export RECORD_SAMPLE_REPO="$BATS_TEST_TMPDIR/sample"
  OUTD="$BATS_TEST_TMPDIR/out"
}

@test "record-fixtures: solo comandi di lettura, nomi con versione, home anonimizzata" {
  _rec_setup
  run "$DEVBAR_REPO/scripts/record-fixtures.sh" "$OUTD"
  [ "$status" -eq 0 ]
  [ -f "$OUTD/brew-outdated-7.0.16.json" ]
  [ -f "$OUTD/rtk-gain-1.2.1.json" ]
  [ -f "$OUTD/npm-audit-11.20.0.json" ]
  [ ! -e "$OUTD/docker-stats-"* ] || false
  [ "$(jq -r .dir "$OUTD/colima-list-0.10.3.json")" = "/Users/anon/.colima" ]
  run grep -rF "$HOME" "$OUTD"
  [ "$status" -ne 0 ]
  # ogni chiamata ai tool è nella lista dei comandi di sola lettura
  local f line
  for f in "$BATS_TEST_TMPDIR"/*.calls; do
    while IFS= read -r line; do
      case "$(basename "$f" .calls) $line" in
        "brew --version" | "brew outdated --json=v2" | "brew vulns --json" | \
          "rtk --version" | "rtk gain -d -f json" | \
          "tokensave --version" | "tokensave gain --all --json --range 7d" | "tokensave discover --json --since 7d" | \
          "colima version" | "colima list --json" | "docker stats --no-stream --format json" | \
          "claude-usage --status" | "claude --version" | "claude plugin list --json" | "npm -v" | "npm audit --json") ;;
        *) echo "chiamata non di sola lettura: $(basename "$f" .calls) $line" >&2; return 1 ;;
      esac
    done <"$f"
  done
}

@test "record-fixtures: rifiuta di scrivere un file con dati personali" {
  _rec_setup
  printf '{"summary":{"total_saved":1},"cwd":"/Users/qualcunaltro/progetto"}\n' >"$FX/rtk/g.json"
  run "$DEVBAR_REPO/scripts/record-fixtures.sh" "$OUTD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RIFIUTO rtk-gain"* ]]
  [ ! -e "$OUTD/rtk-gain-1.2.1.json" ]
  [ -f "$OUTD/brew-outdated-7.0.16.json" ]
}

@test "record-fixtures: rifiuta una riga con /Users/anon e un altro utente" {
  _rec_setup
  printf '{"summary":{"total_saved":1},"a":"/Users/anon/x","b":"/Users/qualcunaltro/y"}\n' >"$FX/rtk/g.json"
  run "$DEVBAR_REPO/scripts/record-fixtures.sh" "$OUTD"
  [ "$status" -eq 1 ]
  [ ! -e "$OUTD/rtk-gain-1.2.1.json" ]
}

@test "record-fixtures: rifiuta un token" {
  _rec_setup
  printf '{"summary":{"total_saved":1},"t":"ghp_abcdefghijklmnopqrstuvwxyz0123456789"}\n' >"$FX/rtk/g.json"
  run "$DEVBAR_REPO/scripts/record-fixtures.sh" "$OUTD"
  [ "$status" -eq 1 ]
  [ ! -e "$OUTD/rtk-gain-1.2.1.json" ]
}

@test "record-fixtures: RECORD_EXTRA_REDACT toglie i nomi dei repo privati" {
  _rec_setup
  printf '{"summary":{"total_saved":1},"repo":"acme-segreto"}\n' >"$FX/rtk/g.json"
  RECORD_EXTRA_REDACT="acme-segreto" run "$DEVBAR_REPO/scripts/record-fixtures.sh" "$OUTD"
  [ "$status" -eq 0 ]
  [ "$(jq -r .repo "$OUTD/rtk-gain-1.2.1.json")" = private-repo ]
}

@test "record-fixtures: un comando fuori lista viene rifiutato" {
  run bash -c "source <(sed -n '/^ro_allowed()/,/^have()/p' '$DEVBAR_REPO/scripts/record-fixtures.sh' | sed '\$d'); ro_allowed brew install wget || echo rifiutato; ro_allowed brew upgrade || echo rifiutato; ro_allowed docker rm x || echo rifiutato"
  [ "$(grep -c rifiutato <<<"$output")" = 3 ]
}

@test "reale: TokenEconomizer da claude plugin list --json" {
  local clone="$BATS_TEST_TMPDIR/te-clone"
  mkdir -p "$clone/plugin/scripts" "$HOME/.claude/plugins"
  printf '#!/bin/sh\n' >"$clone/plugin/scripts/te"; chmod +x "$clone/plugin/scripts/te"
  jq -nc --arg p "$clone" '{tokeneconomizer:{source:{source:"directory",path:$p}}}' >"$HOME/.claude/plugins/known_marketplaces.json"
  export STUB_CLAUDE_PLUGIN_FIXTURE="$(latest claude-plugin-list)"
  run --separate-stderr "$DEVBAR" run ai-status tokeneconomizer
  [ "$status" -eq 0 ]
  [ "$(jq -r '.harnesses[] | select(.id=="claude").state' <<<"$output")" = installed ]
  schema_ok ai-status "$output"
}
