#!/usr/bin/env bash
# devbar: check Homebrew (brew-outdated).

# check_brew_outdated: formule e cask da aggiornare (esclusi brewExclude e pinned).
check_brew_outdated() {
  require_tool brew
  local raw json exclude items count
  raw="$(brew outdated --json=v2 2>/dev/null || true)"
  # il JSON parte dalla prima riga che inizia con '{' (brew può stampare '==> ...' prima)
  json="$(printf '%s\n' "$raw" | awk '/^\{/ {p=1} p')"
  if [ -z "$json" ] || ! jq -e 'type == "object"' <<<"$json" >/dev/null 2>&1; then
    emit error 0 "output di brew outdated non valido"
  fi
  exclude="$(config_get .brewExclude)"
  items="$(jq -c --argjson ex "$exclude" '
    def last_ver: if type == "array" then (.[-1] // "") else (. // "") end;
    [ (.formulae // [])[] | select((.pinned // false) | not)
        | {name, kind: "formula", installed: (.installed_versions | last_ver), current: .current_version} ]
    + [ (.casks // [])[]
        | {name, kind: "cask", installed: (.installed_versions | last_ver), current: .current_version} ]
    | map(select(.name as $n | $ex | index($n) | not))' <<<"$json")" ||
    emit error 0 "output di brew outdated non valido"
  count="$(jq 'length' <<<"$items")"
  if [ "$count" -eq 0 ]; then
    emit ok 0 "Homebrew aggiornato" "[]"
  fi
  emit action "$count" "$count pacchetti da aggiornare" "$items"
}

# check_brew_vulns: vulnerabilità note (OSV) delle formule installate, cache 24h.
# Solo findings[].vulnerabilities conta (come scan_brew_vulns di Sparkdock,
# github.com/sparkfabrik/sparkdock, GPLv3). `brew vulns` esce != 0 se trova
# vulnerabilità: si legge solo il JSON.
check_brew_vulns() {
  local force="${1:-}" json raw items count severe
  require_tool brew
  if [ "$force" = "--force" ] || ! cache_fresh brew-vulns 1440; then
    export HOMEBREW_NO_AUTO_UPDATE=1
    # brew senza `vulns` non può scansionare: non è una scansione fallita
    brew vulns --help >/dev/null 2>&1 || emit unconfigured 0 "brew vulns non disponibile"
    raw="$(brew vulns --json 2>/dev/null || true)"
    json="$(printf '%s\n' "$raw" | awk '/^\{/ {p=1} p')"
    if [ -z "$json" ] || ! jq -e '
        type == "object" and (.findings | type == "array")
        and all(.findings[]; (.vulnerabilities | type == "array"))' <<<"$json" >/dev/null 2>&1; then
      emit error 0 "output di brew vulns non valido"
    fi
    printf '%s\n' "$json" | cache_write brew-vulns
  fi
  items="$(cache_read brew-vulns | jq -c '
    [ .findings[] | .formula as $f | .vulnerabilities[]
      | {formula: $f, id, severity: (.severity // "UNKNOWN"),
         fixAvailable: ((.fixed_versions // []) | length > 0)} ]')" ||
    emit error 0 "cache di brew vulns non valida"
  count="$(jq 'length' <<<"$items")"
  severe="$(jq '[.[] | select(.severity | ascii_upcase | . == "HIGH" or . == "CRITICAL")] | length' <<<"$items")"
  # emit esce dal sottoprocesso della pipeline: rc preso da PIPESTATUS
  if [ "$count" -eq 0 ]; then
    emit ok 0 "Nessuna vulnerabilità Homebrew" "[]" | jq --argjson s 0 '. + {severe:$s}'
  else
    emit action "$count" "$count vulnerabilità Homebrew ($severe alte o critiche)" "$items" |
      jq --argjson s "$severe" '. + {severe:$s}'
  fi
  exit "${PIPESTATUS[0]}"
}
