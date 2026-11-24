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
