#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub rtk tokensave claude-usage
  DEVBAR="$DEVBAR_REPO/bin/devbar"
}

absent() { # absent <tool> <check>
  rm -f "$BATS_TEST_TMPDIR/stubs/$1"
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" "$(command -v bash)" "$DEVBAR" check "$2"
}

@test "rtk: 10 giorni -> daily ultimi 7" {
  export STUB_RTK_FIXTURE=gain-10days.json
  run --separate-stderr "$DEVBAR" check rtk
  [ "$status" -eq 1 ]
  [ "$(jq -r '.daily|length' <<<"$output")" = 7 ]
  [ "$(jq -r '.daily[0].date' <<<"$output")" = 2026-11-13 ]
  [ "$(jq -r '.daily[6].saved' <<<"$output")" = 409 ]
  [ "$(jq -r .saved <<<"$output")" = 185865 ]
  [ "$(jq -r .input <<<"$output")" = 1013655 ]
  [ "$(jq -r .commands <<<"$output")" = 2784 ]
  [ "$(jq -r '.pct|floor' <<<"$output")" = 18 ]
  grep -qx "gain -d -f json" "$BATS_TEST_TMPDIR/rtk.calls"
}

@test "rtk: daily vuoto" {
  export STUB_RTK_FIXTURE=gain-empty.json
  run --separate-stderr "$DEVBAR" check rtk
  [ "$status" -eq 1 ]
  [ "$(jq -c .daily <<<"$output")" = "[]" ]
}

@test "rtk: output rotto -> rc 2" {
  export STUB_RTK_FIXTURE=gain-broken.txt
  run --separate-stderr "$DEVBAR" check rtk
  [ "$status" -eq 2 ]
  [ "$(jq -r .status <<<"$output")" = error ]
}

@test "rtk: assente -> rc 3" {
  absent rtk rtk
  [ "$status" -eq 3 ]
  [ "$(jq -r .status <<<"$output")" = unconfigured ]
}

@test "tokensave: gain + discover con preambolo" {
  export STUB_TOKENSAVE_GAIN_FIXTURE=gain.json STUB_TOKENSAVE_DISCOVER_FIXTURE=discover-preamble.txt
  run --separate-stderr "$DEVBAR" check tokensave
  [ "$status" -eq 1 ]
  [ "$(jq -r .saved <<<"$output")" = 1234 ]
  [ "$(jq -r .calls <<<"$output")" = 17 ]
  [ "$(jq -r .usd <<<"$output")" = 0.42 ]
  [ "$(jq -r .missedTurns <<<"$output")" = 33 ]
  grep -qx "gain --all --json --range 7d" "$BATS_TEST_TMPDIR/tokensave.calls"
  grep -qx "discover --json --since 7d" "$BATS_TEST_TMPDIR/tokensave.calls"
}

@test "tokensave: gain rotto -> rc 2" {
  export STUB_TOKENSAVE_GAIN_FIXTURE=gain.json STUB_TOKENSAVE_GAIN_RC=0
  export STUB_TOKENSAVE_DISCOVER_FIXTURE=discover-empty.json
  run --separate-stderr "$DEVBAR" check tokensave
  [ "$(jq -r .missedTurns <<<"$output")" = 0 ]
  export STUB_TOKENSAVE_GAIN_FIXTURE=../rtk/gain-broken.txt
  run --separate-stderr "$DEVBAR" check tokensave
  [ "$status" -eq 2 ]
}

@test "tokensave: discover rotto -> rc 2" {
  export STUB_TOKENSAVE_GAIN_FIXTURE=gain.json STUB_TOKENSAVE_DISCOVER_FIXTURE=../rtk/gain-broken.txt
  run --separate-stderr "$DEVBAR" check tokensave
  [ "$status" -eq 2 ]
}

@test "tokensave: assente -> rc 3" {
  absent tokensave tokensave
  [ "$status" -eq 3 ]
}

@test "caveman: config + cartella versione" {
  mkdir -p "$HOME/.config/caveman" "$HOME/.claude/plugins/cache/caveman/caveman/4.2.0" "$HOME/.claude/plugins/cache/caveman/caveman/4.10.0" "$HOME/.claude/plugins/cache/caveman/caveman/4.9.1"
  echo '{"defaultMode":"full"}' >"$HOME/.config/caveman/config.json"
  run --separate-stderr "$DEVBAR" check caveman
  [ "$status" -eq 1 ]
  [ "$(jq -r .mode <<<"$output")" = caveman ]
  [ "$(jq -r .rawMode <<<"$output")" = full ]
  [ "$(jq -r .version <<<"$output")" = 4.10.0 ]
  [ "$(jq -r .pluginEnabled <<<"$output")" = false ]
  [ "$(jq -r .active <<<"$output")" = false ]
  [ "$(jq 'has("saved") or has("pct") or has("daily")' <<<"$output")" = false ]
}

@test "caveman: plugin abilitato + modalità -> active" {
  mkdir -p "$HOME/.config/caveman" "$HOME/.claude"
  echo '{"defaultMode":"wenyan-ultra"}' >"$HOME/.config/caveman/config.json"
  echo '{"enabledPlugins":{"caveman@caveman":true}}' >"$HOME/.claude/settings.json"
  run --separate-stderr "$DEVBAR" check caveman
  [ "$status" -eq 1 ]
  [ "$(jq -r .mode <<<"$output")" = megacave ]
  [ "$(jq -r .rawMode <<<"$output")" = wenyan-ultra ]
  [ "$(jq -r .pluginEnabled <<<"$output")" = true ]
  [ "$(jq -r .active <<<"$output")" = true ]
}

@test "caveman: modalità off -> non active anche con plugin abilitato" {
  mkdir -p "$HOME/.config/caveman" "$HOME/.claude"
  echo '{"defaultMode":"off"}' >"$HOME/.config/caveman/config.json"
  echo '{"enabledPlugins":{"caveman@caveman":true}}' >"$HOME/.claude/settings.json"
  run --separate-stderr "$DEVBAR" check caveman
  [ "$(jq -r .mode <<<"$output")" = off ]
  [ "$(jq -r .active <<<"$output")" = false ]
}

@test "caveman: lastMode da config devbar, default caveman" {
  mkdir -p "$HOME/.claude/plugins/cache/caveman/caveman/4.2.0"
  run --separate-stderr "$DEVBAR" check caveman
  [ "$(jq -r .lastMode <<<"$output")" = caveman ]
  write_config '{"cavemanLastMode":"megacave"}'
  run --separate-stderr "$DEVBAR" check caveman
  [ "$(jq -r .lastMode <<<"$output")" = megacave ]
}

@test "caveman: plugin senza config -> modalità di default caveman" {
  mkdir -p "$HOME/.claude/plugins/cache/caveman/caveman/4.2.0"
  echo '{"enabledPlugins":{"caveman@caveman":true}}' >"$HOME/.claude/settings.json"
  run --separate-stderr "$DEVBAR" check caveman
  [ "$(jq -r .mode <<<"$output")" = caveman ]
  [ "$(jq -r .rawMode <<<"$output")" = "" ]
  [ "$(jq -r .active <<<"$output")" = true ]
}

@test "caveman: solo cartella" {
  mkdir -p "$HOME/.claude/plugins/cache/caveman/caveman/4.2.0"
  run --separate-stderr "$DEVBAR" check caveman
  [ "$status" -eq 1 ]
  [ "$(jq -r .version <<<"$output")" = 4.2.0 ]
  [ "$(jq -r .mode <<<"$output")" = caveman ]
}

@test "caveman: solo config" {
  mkdir -p "$HOME/.config/caveman"
  echo '{"defaultMode":"ultra"}' >"$HOME/.config/caveman/config.json"
  run --separate-stderr "$DEVBAR" check caveman
  [ "$status" -eq 1 ]
  [ "$(jq -r .mode <<<"$output")" = ultracave ]
  [ "$(jq -r .rawMode <<<"$output")" = ultra ]
}

@test "caveman: config rotto + niente cartella -> rc 3" {
  mkdir -p "$HOME/.config/caveman"
  echo '{broken' >"$HOME/.config/caveman/config.json"
  run --separate-stderr "$DEVBAR" check caveman
  [ "$status" -eq 3 ]
}

@test "caveman: assente -> rc 3" {
  run --separate-stderr "$DEVBAR" check caveman
  [ "$status" -eq 3 ]
  [ "$(jq -r .status <<<"$output")" = unconfigured ]
}

@test "claude-usage: --status, campi in .usage" {
  export STUB_CLAUDE_USAGE_FIXTURE=status.json
  run --separate-stderr "$DEVBAR" check claude-usage
  [ "$status" -eq 1 ]
  [ "$(jq -r .usage.c_pct <<<"$output")" = 42 ]
  [ "$(jq -r .usage.w_pct <<<"$output")" = 67 ]
  [ "$(jq -r .usage.c_reset <<<"$output")" = "3h 12m" ]
  [ "$(jq -r .usage.stale <<<"$output")" = false ]
  [ "$(jq -r .usage.auth <<<"$output")" = valid ]
  [ "$(jq -r .usage.error <<<"$output")" = null ]
  grep -qx -- "--status" "$BATS_TEST_TMPDIR/claude-usage.calls"
}

@test "claude-usage: auth missing inoltrato com'è (stringa), con error" {
  export STUB_CLAUDE_USAGE_FIXTURE=status-missing.json
  run --separate-stderr "$DEVBAR" check claude-usage
  [ "$status" -eq 1 ]
  [ "$(jq -r .usage.auth <<<"$output")" = missing ]
  [ "$(jq -r .usage.error <<<"$output")" = "no credentials found" ]
}

@test "claude-usage: --force -> --force-poll" {
  export STUB_CLAUDE_USAGE_FIXTURE=status.json
  run --separate-stderr "$DEVBAR" check claude-usage --force
  [ "$status" -eq 1 ]
  grep -qx -- "--status --force-poll" "$BATS_TEST_TMPDIR/claude-usage.calls"
}

@test "claude-usage: output rotto -> rc 2" {
  export STUB_CLAUDE_USAGE_FIXTURE=broken.txt
  run --separate-stderr "$DEVBAR" check claude-usage
  [ "$status" -eq 2 ]
}

@test "claude-usage: assente -> rc 3" {
  absent claude-usage claude-usage
  [ "$status" -eq 3 ]
}
