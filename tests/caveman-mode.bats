#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  DEVBAR="$DEVBAR_REPO/bin/devbar"
  CFG="$HOME/.config/caveman/config.json"
}

@test "caveman-mode: modalità non valida -> rc 2, nessuna scrittura" {
  run --separate-stderr "$DEVBAR" run caveman-mode commit --yes
  [ "$status" -eq 2 ]
  run --separate-stderr "$DEVBAR" run caveman-mode
  [ "$status" -eq 2 ]
  [ ! -e "$CFG" ]
}

@test "caveman-mode: senza --yes stampa il piano e non scrive" {
  run --separate-stderr "$DEVBAR" run caveman-mode ultracave
  [ "$status" -eq 0 ]
  [ "$(jq -r .plan <<<"$output")" = true ]
  [ "$(jq -r .value <<<"$output")" = ultracave ]
  [[ "$(jq -r '.commands | join(" ")' <<<"$output")" == *"vale per le nuove sessioni"* ]]
  [ ! -e "$CFG" ]
}

@test "caveman-mode: --yes crea il file se manca" {
  run --separate-stderr "$DEVBAR" run caveman-mode megacave --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r .defaultMode "$CFG")" = megacave ]
}

@test "caveman-mode: --yes preserva le altre chiavi" {
  mkdir -p "$(dirname "$CFG")"
  echo '{"defaultMode":"full","reinforce":true}' >"$CFG"
  run --separate-stderr "$DEVBAR" run caveman-mode manual --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r .defaultMode "$CFG")" = manual ]
  [ "$(jq -r .reinforce "$CFG")" = true ]
}

@test "caveman-mode: off ricorda la modalità canonica precedente" {
  mkdir -p "$(dirname "$CFG")"
  echo '{"defaultMode":"ultra"}' >"$CFG"
  run --separate-stderr "$DEVBAR" run caveman-mode off --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r .defaultMode "$CFG")" = off ]
  [ "$(jq -r .cavemanLastMode "$DEVBAR_CONFIG")" = ultracave ]
  # off -> off non sovrascrive il ricordo
  run --separate-stderr "$DEVBAR" run caveman-mode off --yes
  [ "$(jq -r .cavemanLastMode "$DEVBAR_CONFIG")" = ultracave ]
}

@test "caveman-mode: config caveman rotta -> rc 2, file intatto" {
  mkdir -p "$(dirname "$CFG")"
  echo '{broken' >"$CFG"
  run --separate-stderr "$DEVBAR" run caveman-mode caveman --yes
  [ "$status" -eq 2 ]
  [ "$(cat "$CFG")" = '{broken' ]
}
