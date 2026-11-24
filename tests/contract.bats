#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Contratto motore <-> app: l'output di ogni comando (prodotto da tests/contract-fixtures.sh
# con stub e HOME temporanea) deve rispettare lo schema in schemas/. Per ogni schema c'è un
# caso negativo: togliere (o sbagliare il tipo di) un campo che l'app legge deve far fallire.
# Richiede check-jsonschema (brew install check-jsonschema).

load helpers

setup_file() {
  command -v check-jsonschema >/dev/null || { echo "check-jsonschema mancante: brew install check-jsonschema" >&2; return 1; }
  FX="$BATS_FILE_TMPDIR/fx"
  bash "$DEVBAR_REPO/tests/contract-fixtures.sh" "$FX"
  export FX
}

# schema_of <fixture>: schemas/<comando>.schema.json (le varianti sono <comando>.<variante>.json).
schema_of() {
  local n
  n="$(basename "$1" .json)"
  printf '%s/schemas/%s.schema.json' "$DEVBAR_REPO" "${n%%.*}"
}

# valid <file> [<fixture>]: valida contro lo schema del fixture.
validate() { check-jsonschema --schemafile "$(schema_of "${2:-$1}")" "$1"; }

# neg <fixture> <filtro jq>: la fixture mutata NON deve validare.
neg() {
  local f="$FX/$1.json" m="$BATS_TEST_TMPDIR/mutated.json"
  jq "$2" "$f" >"$m"
  ! cmp -s "$f" "$m"
  run validate "$m" "$f"
  [ "$status" -ne 0 ]
}

@test "ogni fixture valida contro il suo schema" {
  local f n=0
  for f in "$FX"/*.json; do
    [ -f "$(schema_of "$f")" ] || { echo "schema mancante per $f" >&2; return 1; }
    run validate "$f"
    [ "$status" -eq 0 ] || { echo "$f: $output" >&2; return 1; }
    n=$((n + 1))
  done
  [ "$n" -ge 22 ]
}

@test "ogni schema ha almeno una fixture" {
  local s name
  for s in "$DEVBAR_REPO"/schemas/*.schema.json; do
    name="$(basename "$s" .schema.json)"
    [ "$name" = defs ] && continue
    compgen -G "$FX/$name.json" >/dev/null || compgen -G "$FX/$name.*.json" >/dev/null || { echo "nessuna fixture per $name" >&2; return 1; }
  done
}

@test "fixture registrate in repo = rigenerate ora (nessuna deriva)" {
  run diff -r "$DEVBAR_REPO/app/Tests/DevbarCoreTests/Fixtures/contract" "$FX"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "fixture senza dati personali" {
  run grep -rEl "$(id -un)|/Users/[a-z]+/(Documents|Library)" "$FX"
  [ "$status" -ne 0 ]
}

@test "negativo: busta dei check senza status/count/summary/items/checkedAt" {
  local c k
  for c in brew-outdated brew-vulns npm-audit composer-audit colima rtk tokensave caveman claude-usage harnesses; do
    for k in status count summary items checkedAt; do neg "$c" "del(.$k)"; done
  done
}

@test "negativo: brew-outdated" { neg brew-outdated 'del(.items[0].name)'; neg brew-outdated '.items[0].kind = "tap"'; neg brew-outdated 'del(.items[0].installed)'; }
@test "negativo: brew-vulns" { neg brew-vulns 'del(.severe)'; neg brew-vulns 'del(.items[0].fixAvailable)'; neg brew-vulns '.items[0].fixAvailable = "no"'; }
@test "negativo: npm-audit" { neg npm-audit 'del(.items[0].repo)'; neg npm-audit 'del(.items[0].high)'; neg npm-audit.error 'del(.items[0].error)'; }
@test "negativo: composer-audit" { neg composer-audit 'del(.items[0].critical)'; neg composer-audit '.items[0].low = "1"'; }
@test "negativo: colima" { neg colima 'del(.profiles)'; neg colima 'del(.containers)'; neg colima 'del(.profiles[0].memoryBytes)'; neg colima '.containers[0].id = 7'; }
@test "negativo: rtk" { neg rtk 'del(.daily)'; neg rtk 'del(.saved)'; neg rtk '.pct = "18"'; neg rtk 'del(.daily[0].date)'; }
@test "negativo: tokensave" { neg tokensave 'del(.missedTurns)'; neg tokensave 'del(.usd)'; neg tokensave '.calls = null'; }
@test "negativo: caveman" { neg caveman 'del(.pluginEnabled)'; neg caveman 'del(.mode)'; neg caveman '.mode = "ultra"'; neg caveman '.lastMode = "off"'; neg caveman '.active = "true"'; }
@test "negativo: claude-usage (auth è una stringa, non un booleano)" {
  neg claude-usage 'del(.usage)'
  neg claude-usage 'del(.usage.auth)'
  neg claude-usage '.usage.auth = true'
  neg claude-usage '.usage.c_pct = "42"'
  neg claude-usage.missing 'del(.usage.error)'
}
@test "negativo: harnesses" { neg harnesses '.items[0] = 5'; neg harnesses '.items[0] = "vim"'; }
@test "negativo: check all" {
  local c
  for c in brew-outdated brew-vulns npm-audit composer-audit colima rtk tokensave caveman claude-usage harnesses; do neg all "del(.[\"$c\"])"; done
  neg all 'del(.colima.profiles)'
  neg all 'del(.rtk.rc)'
  neg all '.caveman.active = 1'
  neg all '.colima = {rc:2,status:"error",summary:"altro"}'
}
@test "negativo: detect" { neg detect 'del(.aiTools)'; neg detect 'del(.tools.cork)'; neg detect 'del(.harnesses[0].managed)'; neg detect '.harnesses[0].installed = "yes"'; }
@test "negativo: repos" { neg repos 'del(.[0].path)'; neg repos 'del(.[0].tokensave)'; neg repos '.[0].npm = 1'; }
@test "negativo: check-timeouts" { neg check-timeouts 'del(."npm-audit")'; neg check-timeouts '.rtk = "60"'; neg check-timeouts '.rtk = 0'; }
@test "negativo: ai-status" { neg ai-status 'del(.installed)'; neg ai-status 'del(.harnesses[0].state)'; neg ai-status '.harnesses[0].state = "ok"'; }
@test "negativo: project-status" { neg project-status 'del(.path)'; neg project-status 'del(.checks[1].willWrite)'; neg project-status '.checks[0].ok = "no"'; neg project-status '.checks |= reverse'; }
@test "negativo: piano senza --yes" { neg plan 'del(.commands)'; neg plan 'del(.plan)'; neg plan '.commands = "rtk init"'; }
@test "negativo: caveman-mode" {
  neg caveman-mode 'del(.value)'
  neg caveman-mode 'del(.applied)'
  neg caveman-mode.plan 'del(.commands)'
  neg caveman-mode.plan 'del(.key)'
  neg caveman-mode.plan '.value = "commit"'
}
@test "negativo: tool-install" { neg tool-install 'del(.terminal)'; neg tool-install '.terminal = false'; }
@test "negativo: journal" {
  neg journal 'del(.entries)'
  neg journal 'del(.entries[0].id)'
  neg journal 'del(.entries[0].undone)'
  neg journal '.entries[0].files[0].existed = "no"'
  neg journal 'del(.entries[0].files[0].sha256After)'
}
@test "negativo: undo" {
  neg undo.plan 'del(.needsForce)'
  neg undo.plan 'del(.files)'
  neg undo.plan '.files[0].action = "delete"'
  neg undo.plan 'del(.id)'
  neg undo 'del(.applied)'
  neg undo 'del(.kept)'
  neg undo.error 'del(.error)'
}
