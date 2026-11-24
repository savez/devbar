#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  export DEVBAR_APPLICATIONS_DIR="$BATS_TEST_TMPDIR/apps"
  mkdir -p "$DEVBAR_APPLICATIONS_DIR"
  DEVBAR="$DEVBAR_REPO/bin/devbar"
  # PATH isolato: niente harness/tool reali della macchina (solo jq + base di sistema)
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -sf "$(command -v jq)" "$BATS_TEST_TMPDIR/bin/jq"
  export PATH="$BATS_TEST_TMPDIR/stubs:$DEVBAR_REPO/tests/stubs:$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
}

@test "detect: harness da cartella e da binario, managed da config" {
  mkdir -p "$HOME/.codex"
  make_stub claude
  write_config '{"harnesses":["claude"]}'
  run --separate-stderr "$DEVBAR" detect
  [ "$status" -eq 0 ]
  [ "$(jq -r '.harnesses[]|select(.id=="codex")|.installed' <<<"$output")" = true ]
  [ "$(jq -r '.harnesses[]|select(.id=="codex")|.managed' <<<"$output")" = false ]
  [ "$(jq -r '.harnesses[]|select(.id=="claude")|.installed' <<<"$output")" = true ]
  [ "$(jq -r '.harnesses[]|select(.id=="claude")|.managed' <<<"$output")" = true ]
  [ "$(jq -r '.harnesses[]|select(.id=="gemini")|.installed' <<<"$output")" = false ]
  [ "$(jq -r '.harnesses|length' <<<"$output")" = 6 ]
}

@test "detect: tools e cork" {
  make_stub rtk brew
  mkdir -p "$DEVBAR_APPLICATIONS_DIR/Cork.app"
  run --separate-stderr "$DEVBAR" detect
  [ "$(jq -r '.tools.rtk' <<<"$output")" = true ]
  [ "$(jq -r '.tools.brew' <<<"$output")" = true ]
  [ "$(jq -r '.tools.cork' <<<"$output")" = true ]
  [ "$(jq -r '.tools|keys|length' <<<"$output")" = 8 ]
}

@test "check harnesses: codex installato non managed -> rc 0 items [codex]" {
  mkdir -p "$HOME/.codex"
  make_stub claude
  write_config '{"harnesses":["claude"]}'
  run --separate-stderr "$DEVBAR" check harnesses
  [ "$status" -eq 0 ]
  [ "$(jq -c .items <<<"$output")" = '["codex"]' ]
}

@test "check harnesses: tutto managed -> rc 1" {
  mkdir -p "$HOME/.codex"
  write_config '{"harnesses":["codex"]}'
  run --separate-stderr "$DEVBAR" check harnesses
  [ "$status" -eq 1 ]
  [ "$(jq -c .items <<<"$output")" = '[]' ]
}

@test "check harnesses: config vuota -> rc 0 elenca gli installati" {
  mkdir -p "$HOME/.codex" "$HOME/.gemini"
  run --separate-stderr "$DEVBAR" check harnesses
  [ "$status" -eq 0 ]
  [ "$(jq -c '.items|sort' <<<"$output")" = '["codex","gemini"]' ]
}

@test "check all: brew fallisce, gli altri presenti" {
  make_stub brew
  export STUB_BREW_RC=1
  run --separate-stderr "$DEVBAR" check all
  [ "$status" -eq 1 ]
  [ "$(jq -r '.["brew-outdated"].rc' <<<"$output")" = 2 ]
  for k in brew-vulns npm-audit composer-audit colima rtk tokensave caveman claude-usage harnesses; do
    [ "$(jq -r --arg k "$k" 'has($k)' <<<"$output")" = true ]
    [ "$(jq -r --arg k "$k" '.[$k]|has("rc")' <<<"$output")" = true ]
  done
  [ "$(jq -r '.harnesses.status' <<<"$output")" = ok ]
}

@test "check all: lock occupato -> busy" {
  mkdir -p "$DEVBAR_CACHE_DIR/devbar.lock.d"
  sleep 30 &
  local p=$!
  echo "$p" >"$DEVBAR_CACHE_DIR/devbar.lock.d/pid"
  run --separate-stderr "$DEVBAR" check all
  kill "$p" 2>/dev/null || true
  [ "$status" -eq 2 ]
  [ "$(jq -r .error <<<"$output")" = busy ]
}

@test "check all: rilascia il lock" {
  run --separate-stderr "$DEVBAR" check all
  [ ! -e "$DEVBAR_CACHE_DIR/devbar.lock.d" ]
}
