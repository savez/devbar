#!/usr/bin/env bash
# devbar: azioni Homebrew e Cork.

# action_brew_upgrade [pkg]: apre `brew upgrade [pkg]` nel terminale.
action_brew_upgrade() {
  if [ $# -gt 0 ]; then
    open_in_terminal brew upgrade "$1"
  else
    open_in_terminal brew upgrade
  fi
}

# action_brew_exclude <pkg>: aggiunge a brewExclude (scrittura atomica, idempotente).
action_brew_exclude() {
  local pkg="${1:-}" file dir tmp base
  [ -n "$pkg" ] || { echo "uso: devbar run brew-exclude <pacchetto>" >&2; return 2; }
  file="$(devbar_config_path)"
  dir="$(dirname "$file")"
  mkdir -p "$dir"
  if [ -f "$file" ]; then
    base="$(cat "$file")"
    if ! jq -e 'type == "object"' <<<"$base" >/dev/null 2>&1; then
      echo "devbar: config non valida: $file (non modificata)" >&2
      return 2
    fi
  else
    base='{}'
  fi
  tmp="$(mktemp "$dir/.config.XXXXXX")"
  if ! jq --arg p "$pkg" '.brewExclude = (((.brewExclude // []) + [$p]) | unique_by(.) )' <<<"$base" >"$tmp"; then
    rm -f "$tmp"
    return 2
  fi
  mv "$tmp" "$file"
}

# action_cork_open: apre Cork.
action_cork_open() { open -a Cork; }

# action_cork_install [--yes]: senza --yes stampa solo il piano.
action_cork_install() {
  if [ "${1:-}" != "--yes" ]; then
    echo "piano: brew install --cask cork (rilancia con --yes per eseguire)"
    return 0
  fi
  brew install --cask cork
}
