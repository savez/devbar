#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub brew
  DEVBAR="$DEVBAR_REPO/bin/devbar"
}

@test "brew-vulns: 2 vuln, 1 HIGH -> rc 0" {
  export STUB_BREW_FIXTURE=vulns-two.json
  run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" = 2 ]
  [ "$(jq -r .severe <<<"$output")" = 1 ]
  [ "$(jq -r '.items[]|select(.id=="CVE-2026-0001").fixAvailable' <<<"$output")" = true ]
  [ "$(jq -r '.items[]|select(.id=="CVE-2026-0002").fixAvailable' <<<"$output")" = false ]
  [ "$(jq -r '.items[0].formula' <<<"$output")" = ffmpeg ]
}

@test "brew-vulns: findings vuoti -> rc 1" {
  export STUB_BREW_FIXTURE=vulns-empty.json
  run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 1 ]
  [ "$(jq -r .status <<<"$output")" = ok ]
}

@test "brew-vulns: rc brew 1 con JSON valido letto normalmente" {
  export STUB_BREW_FIXTURE=vulns-two.json
  export STUB_BREW_VULNS_RC=1
  export STUB_BREW_VULNS_HELP_RC=0
  run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" = 2 ]
}

@test "brew-vulns: preambolo prima del JSON" {
  export STUB_BREW_FIXTURE=vulns-preamble.txt
  run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" = 2 ]
}

@test "brew-vulns: findings non lista -> rc 2" {
  export STUB_BREW_FIXTURE=vulns-badshape.json
  run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 2 ]
}

@test "brew-vulns: output vuoto -> rc 2" {
  run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 2 ]
}

@test "brew-vulns: cache 24h, --force la salta" {
  export STUB_BREW_FIXTURE=vulns-two.json
  run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 0 ]
  run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" = 2 ]
  [ "$(grep -c '^vulns --json' "$BATS_TEST_TMPDIR/brew.calls")" -eq 1 ]
  run --separate-stderr "$DEVBAR" check brew-vulns --force
  [ "$status" -eq 0 ]
  [ "$(grep -c '^vulns --json' "$BATS_TEST_TMPDIR/brew.calls")" -eq 2 ]
}

@test "brew-vulns: brew senza sottocomando vulns -> rc 3" {
  export STUB_BREW_FIXTURE=vulns-two.json
  export STUB_BREW_VULNS_HELP_RC=1
  run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 3 ]
}

@test "brew-vulns: brew assente -> rc 3" {
  PATH="/usr/bin:/bin" run --separate-stderr "$DEVBAR" check brew-vulns
  [ "$status" -eq 3 ]
}
