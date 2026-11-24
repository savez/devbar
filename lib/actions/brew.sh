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

# action_brew_exclude <pkg>: aggiunge a brewExclude (config_update, idempotente).
action_brew_exclude() {
  local pkg="${1:-}"
  [ -n "$pkg" ] || { echo "uso: devbar run brew-exclude <pacchetto>" >&2; return 2; }
  # shellcheck disable=SC2016 # filtro jq, non espansione di shell
  config_update '.brewExclude = (((.brewExclude // []) + [$p]) | unique_by(.))' --arg p "$pkg" || return 2
}

# action_cork_open: apre Cork.
action_cork_open() { open -a Cork; }

# action_cork_install [--yes]: senza --yes stampa solo il piano; con --yes nel terminale.
action_cork_install() {
  if [ "${1:-}" != "--yes" ]; then
    echo "piano: brew install --cask cork (rilancia con --yes per eseguire)"
    return 0
  fi
  open_in_terminal brew install --cask cork
}
