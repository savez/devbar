#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub brew osascript
  DEVBAR="$DEVBAR_REPO/bin/devbar"
}

@test "brew-outdated: esclude brewExclude e pinned" {
  write_config '{"brewExclude":["wget"]}'
  export STUB_BREW_FIXTURE=outdated.json
  run --separate-stderr "$DEVBAR" check brew-outdated
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" = 2 ]
  [ "$(jq -r '[.items[].name]|sort|join(",")' <<<"$output")" = "cork,jq" ]
  [ "$(jq -r '.items[]|select(.name=="cork").kind' <<<"$output")" = cask ]
  [ "$(jq -r '.items[]|select(.name=="jq").installed' <<<"$output")" = 1.7 ]
  [ "$(jq -r '.items[]|select(.name=="jq").current' <<<"$output")" = 1.7.1 ]
  [ "$(jq -r '.items[]|select(.name=="cork").installed' <<<"$output")" = 1.0 ]
}

@test "brew-outdated: nulla da aggiornare -> rc 1" {
  export STUB_BREW_FIXTURE=outdated-empty.json
  run --separate-stderr "$DEVBAR" check brew-outdated
  [ "$status" -eq 1 ]
  [ "$(jq -r .status <<<"$output")" = ok ]
}

@test "brew-outdated: preambolo prima del JSON" {
  export STUB_BREW_FIXTURE=outdated-preamble.txt
  run --separate-stderr "$DEVBAR" check brew-outdated
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" = 3 ]
}

@test "brew-outdated: output senza JSON -> rc 2" {
  export STUB_BREW_FIXTURE=outdated-broken.txt
  run --separate-stderr "$DEVBAR" check brew-outdated
  [ "$status" -eq 2 ]
}

@test "brew-outdated: brew assente -> rc 3" {
  rm -f "$BATS_TEST_TMPDIR/stubs/brew"
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" "$(command -v bash)" "$DEVBAR" check brew-outdated
  [ "$status" -eq 3 ]
}

@test "run brew-upgrade apre il terminale con il comando" {
  run "$DEVBAR" run brew-upgrade wget
  [ "$status" -eq 0 ]
  grep -q 'brew upgrade wget' "$BATS_TEST_TMPDIR/osascript.calls"
  grep -q 'Terminal' "$BATS_TEST_TMPDIR/osascript.calls"
}

@test "run brew-upgrade senza pacchetto: brew upgrade" {
  run "$DEVBAR" run brew-upgrade
  [ "$status" -eq 0 ]
  grep -q 'brew upgrade' "$BATS_TEST_TMPDIR/osascript.calls"
}

@test "open_in_terminal: iTerm e sconosciuto" {
  write_config '{"terminal":"iTerm"}'
  run "$DEVBAR" run brew-upgrade wget
  grep -q 'iTerm' "$BATS_TEST_TMPDIR/osascript.calls"
  rm "$BATS_TEST_TMPDIR/osascript.calls"
  write_config '{"terminal":"Boh"}'
  run "$DEVBAR" run brew-upgrade wget
  grep -q 'Terminal' "$BATS_TEST_TMPDIR/osascript.calls"
}

@test "open_in_terminal: quota i caratteri speciali" {
  run "$DEVBAR" run brew-upgrade 'a"b;c'
  [ "$status" -eq 0 ]
  ! grep -q 'a"b;c' "$BATS_TEST_TMPDIR/osascript.calls"
  grep -qF 'a\\\"b\\;c' "$BATS_TEST_TMPDIR/osascript.calls"
}

@test "run brew-exclude: idempotente, preserva le altre chiavi" {
  write_config '{"scanDepth":7}'
  run "$DEVBAR" run brew-exclude wget
  [ "$status" -eq 0 ]
  run "$DEVBAR" run brew-exclude wget
  [ "$status" -eq 0 ]
  [ "$(jq -c .brewExclude "$DEVBAR_CONFIG")" = '["wget"]' ]
  [ "$(jq .scanDepth "$DEVBAR_CONFIG")" = 7 ]
}

@test "run brew-exclude: crea il config se manca" {
  export DEVBAR_CONFIG="$BATS_TEST_TMPDIR/sub/dir/config.json"
  run "$DEVBAR" run brew-exclude jq
  [ "$status" -eq 0 ]
  [ "$(jq -c .brewExclude "$DEVBAR_CONFIG")" = '["jq"]' ]
}

@test "run brew-exclude: config rotto non viene sovrascritto" {
  echo '{rotto' >"$DEVBAR_CONFIG"
  run "$DEVBAR" run brew-exclude jq
  [ "$status" -eq 2 ]
  [ "$(cat "$DEVBAR_CONFIG")" = '{rotto' ]
}

@test "run brew-exclude senza pacchetto -> rc 2" {
  run "$DEVBAR" run brew-exclude
  [ "$status" -eq 2 ]
}

@test "run cork-install senza --yes: stampa il piano, non chiama brew" {
  run "$DEVBAR" run cork-install
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew install --cask cork"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/brew.calls" ]
}

@test "run cork-install --yes: brew install nel terminale, non qui" {
  run "$DEVBAR" run cork-install --yes
  [ "$status" -eq 0 ]
  grep -q 'brew install --cask cork' "$BATS_TEST_TMPDIR/osascript.calls"
  [ ! -e "$BATS_TEST_TMPDIR/brew.calls" ]
}

@test "run cork-open: apre Cork" {
  make_stub open
  run "$DEVBAR" run cork-open
  [ "$status" -eq 0 ]
  grep -q 'Cork' "$BATS_TEST_TMPDIR/open.calls"
}

@test "run open-terminal <path> apre il terminale con cd" {
  mkdir -p "$BATS_TEST_TMPDIR/repo"
  run "$DEVBAR" run open-terminal "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 0 ]
  grep -qF "cd $BATS_TEST_TMPDIR/repo" "$BATS_TEST_TMPDIR/osascript.calls"
}

@test "run open-terminal: cartella inesistente o senza argomento falliscono" {
  run "$DEVBAR" run open-terminal "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  run "$DEVBAR" run open-terminal
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/osascript.calls" ]
}

@test "run open-terminal: iTerm e Ghostty restano in una shell dopo il cd" {
  mkdir -p "$BATS_TEST_TMPDIR/repo"
  local t
  for t in iTerm Ghostty; do
    rm -f "$BATS_TEST_TMPDIR/osascript.calls"
    write_config "{\"terminal\":\"$t\"}"
    run "$DEVBAR" run open-terminal "$BATS_TEST_TMPDIR/repo"
    [ "$status" -eq 0 ]
    grep -q "$t" "$BATS_TEST_TMPDIR/osascript.calls"
    grep -qF 'sh -c cd' "$BATS_TEST_TMPDIR/osascript.calls"
    grep -qF "$BATS_TEST_TMPDIR/repo" "$BATS_TEST_TMPDIR/osascript.calls"
    grep -qF 'exec' "$BATS_TEST_TMPDIR/osascript.calls"
    grep -qF 'SHELL' "$BATS_TEST_TMPDIR/osascript.calls"
  done
}
