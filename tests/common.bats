#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

setup() { setup_env; }

@test "check sconosciuto -> rc 2" {
  run --separate-stderr "$DEVBAR_REPO/bin/devbar" check nope
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"check sconosciuto: nope"* ]]
}

@test "config_get default senza config" {
  run in_common 'config_get .scanDepth'
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "config_get legge il config" {
  write_config '{"scanDepth":2}'
  run in_common 'config_get .scanDepth'
  [ "$output" = "2" ]
}

@test "config_get config rotto -> default e avviso" {
  write_config '{rotto'
  run --separate-stderr in_common 'config_get .scanDepth'
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
  [[ "$stderr" == *"config non valida"* ]]
}

@test "emit ok -> rc 1 e JSON" {
  run --separate-stderr in_common 'emit ok 0 "a posto"'
  [ "$status" -eq 1 ]
  [ "$(jq -r .status <<<"$output")" = "ok" ]
  [ "$(jq -r .count <<<"$output")" = "0" ]
  [ "$(jq -r .summary <<<"$output")" = "a posto" ]
  [ "$(jq -c .items <<<"$output")" = "[]" ]
  jq -e '.checkedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' <<<"$output"
}

@test "emit exit code per status" {
  run in_common 'emit action 1 x'; [ "$status" -eq 0 ]
  run in_common 'emit error 0 x'; [ "$status" -eq 2 ]
  run in_common 'emit unconfigured 0 x'; [ "$status" -eq 3 ]
  run in_common 'emit boh 0 x'; [ "$status" -eq 2 ]
}

@test "emit con items" {
  run in_common 'emit action 1 "uno" "[{\"a\":1}]"'
  [ "$status" -eq 0 ]
  [ "$(jq -c .items <<<"$output")" = '[{"a":1}]' ]
}

@test "require_tool assente -> unconfigured rc 3" {
  run in_common 'require_tool tool-inesistente-xyz'
  [ "$status" -eq 3 ]
  [ "$(jq -r .status <<<"$output")" = "unconfigured" ]
  [[ "$(jq -r .summary <<<"$output")" == *"tool-inesistente-xyz non installato"* ]]
}

@test "require_tool presente -> rc 0" {
  run in_common 'require_tool bash'
  [ "$status" -eq 0 ]
}

@test "cache_write + cache_fresh" {
  run in_common 'echo "{\"a\":1}" | cache_write x; cache_fresh x 1440'
  [ "$status" -eq 0 ]
  run in_common 'cache_read x'
  [ "$output" = '{"a":1}' ]
}

@test "cache_fresh scaduta" {
  in_common 'echo "{}" | cache_write x'
  touch -t "$(date -v-1441M +%Y%m%d%H%M.%S)" "$DEVBAR_CACHE_DIR/x.json"
  run in_common 'cache_fresh x 1440'
  [ "$status" -eq 1 ]
}

@test "cache_fresh assente -> rc 1" {
  run in_common 'cache_fresh nulla 1440'
  [ "$status" -eq 1 ]
}

@test "with_lock: il secondo in parallelo e' busy" {
  in_common 'with_lock sleep 1' >"$BATS_TEST_TMPDIR/a.out" 2>/dev/null &
  p1=$!
  sleep 0.3
  run --separate-stderr in_common 'with_lock sleep 1'
  [ "$status" -eq 2 ]
  [ "$(jq -r .error <<<"$output")" = "busy" ]
  [ "$(jq -r .status <<<"$output")" = "error" ]
  wait "$p1"
}

@test "with_lock rilascia il lock" {
  run in_common 'with_lock true; with_lock true'
  [ "$status" -eq 0 ]
}

@test "with_lock rilascia il lock anche se il comando chiama emit" {
  run in_common 'f() { emit ok 0 fatto; }; with_lock f'
  [ "$status" -eq 1 ]
  [ ! -e "$DEVBAR_CACHE_DIR/devbar.lock.d" ]
  run in_common 'with_lock true'
  [ "$status" -eq 0 ]
}
