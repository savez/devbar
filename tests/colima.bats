#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub colima docker brew osascript
  DEVBAR="$DEVBAR_REPO/bin/devbar"
}

@test "colima: profilo Running + 2 container" {
  export STUB_COLIMA_FIXTURE=list-running.json STUB_DOCKER_FIXTURE=stats-two.json
  run --separate-stderr "$DEVBAR" check colima
  [ "$status" -eq 1 ]
  [ "$(jq -r .status <<<"$output")" = ok ]
  [ "$(jq -r .count <<<"$output")" = 1 ]
  [ "$(jq -r '.profiles[0].cpus' <<<"$output")" = 4 ]
  [ "$(jq -r '.profiles[0].name' <<<"$output")" = default ]
  [ "$(jq -r '.profiles[0].memoryBytes' <<<"$output")" = 8589934592 ]
  [ "$(jq -r '.profiles[0].diskBytes' <<<"$output")" = 64424509440 ]
  [ "$(jq -r '.containers|length' <<<"$output")" = 2 ]
  [ "$(jq -r '.containers[0].id' <<<"$output")" = abc123def456 ]
  [ "$(jq -r '.containers[0].name' <<<"$output")" = web ]
  [ "$(jq -r '.containers[0].cpu' <<<"$output")" = "0.15%" ]
  [ "$(jq -r '.containers[0].mem' <<<"$output")" = "50.2MiB" ]
  grep -q "list --json" "$BATS_TEST_TMPDIR/colima.calls"
}

@test "colima: profilo Stopped -> docker mai chiamato" {
  export STUB_COLIMA_FIXTURE=list-stopped.json STUB_DOCKER_FIXTURE=stats-two.json
  run --separate-stderr "$DEVBAR" check colima
  [ "$status" -eq 1 ]
  [ "$(jq -r .count <<<"$output")" = 0 ]
  [ "$(jq -c .containers <<<"$output")" = "[]" ]
  [ "$(jq -r '.profiles[0].status' <<<"$output")" = Stopped ]
  [ ! -e "$BATS_TEST_TMPDIR/docker.calls" ]
}

@test "colima: nessun profilo -> ok, docker mai chiamato" {
  run --separate-stderr "$DEVBAR" check colima
  [ "$status" -eq 1 ]
  [ "$(jq -c .profiles <<<"$output")" = "[]" ]
  [ ! -e "$BATS_TEST_TMPDIR/docker.calls" ]
}

@test "colima: docker fallisce -> containers [], rc 1, avviso" {
  export STUB_COLIMA_FIXTURE=list-running.json STUB_DOCKER_RC=1
  run --separate-stderr "$DEVBAR" check colima
  [ "$status" -eq 1 ]
  [ "$(jq -c .containers <<<"$output")" = "[]" ]
  [ "$(jq -r .count <<<"$output")" = 1 ]
  [[ "$stderr" == *docker* ]]
}

@test "colima: assente -> rc 3" {
  rm -f "$BATS_TEST_TMPDIR/stubs/colima"
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" "$(command -v bash)" "$DEVBAR" check colima
  [ "$status" -eq 3 ]
  [ "$(jq -r .status <<<"$output")" = unconfigured ]
}

@test "colima-stop default -> colima stop default" {
  run "$DEVBAR" run colima-stop default
  [ "$status" -eq 0 ]
  grep -qx "stop default" "$BATS_TEST_TMPDIR/colima.calls"
}

@test "colima-start senza profilo -> colima start" {
  run "$DEVBAR" run colima-start
  [ "$status" -eq 0 ]
  grep -qx "start" "$BATS_TEST_TMPDIR/colima.calls"
}

@test "colima-start profilo non valido -> rc 2, niente chiamate" {
  run --separate-stderr "$DEVBAR" run colima-start 'a b;rm'
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/colima.calls" ]
}

@test "container-stop <id> -> docker stop" {
  run "$DEVBAR" run container-stop abc123
  [ "$status" -eq 0 ]
  grep -qx "stop abc123" "$BATS_TEST_TMPDIR/docker.calls"
}

@test "container-stop id non valido o mancante -> rc 2" {
  run --separate-stderr "$DEVBAR" run container-stop '$(x)'
  [ "$status" -eq 2 ]
  run --separate-stderr "$DEVBAR" run container-stop
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/docker.calls" ]
}

@test "colima-install senza --yes: solo piano" {
  run "$DEVBAR" run colima-install
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew install colima docker"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/brew.calls" ]
}

@test "colima-install --yes -> brew install colima docker" {
  run "$DEVBAR" run colima-install --yes
  [ "$status" -eq 0 ]
  grep -qx "install colima docker" "$BATS_TEST_TMPDIR/brew.calls"
}

@test "colima-logs apre docker logs -f nel terminale" {
  run "$DEVBAR" run colima-logs abc123
  [ "$status" -eq 0 ]
  grep -q "docker logs -f abc123" "$BATS_TEST_TMPDIR/osascript.calls"
}

@test "colima-logs id non valido -> rc 2" {
  run --separate-stderr "$DEVBAR" run colima-logs 'x y'
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/osascript.calls" ]
}
