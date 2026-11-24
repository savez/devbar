#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub npm composer
  DEVBAR="$DEVBAR_REPO/bin/devbar"
  R="$BATS_TEST_TMPDIR/root"
  mkdir -p "$R/a/node_modules/x" "$R/b/c" "$R/deep/1/2/3/4/5" "$R/a/.tokensave"
  : >"$R/a/package-lock.json"
  : >"$R/a/node_modules/x/package-lock.json"
  : >"$R/b/c/composer.lock"
  : >"$R/deep/1/2/3/4/5/package-lock.json"
  write_config "{\"repoRoots\":[\"$R\"],\"scanDepth\":4}"
}

@test "repos: trova a e b/c, non node_modules ne' oltre scanDepth" {
  run --separate-stderr "$DEVBAR" repos
  [ "$status" -eq 0 ]
  [ "$(jq -r 'map(.path)|sort|join(",")' <<<"$output")" = "$R/a,$R/b/c" ]
  [ "$(jq -r '.[]|select(.name=="a")|[.npm,.composer,.tokensave]|join(",")' <<<"$output")" = "true,false,true" ]
  [ "$(jq -r '.[]|select(.name=="c")|[.npm,.composer,.tokensave]|join(",")' <<<"$output")" = "false,true,false" ]
}

@test "repos: root inesistente saltata con avviso, rc 0" {
  write_config "{\"repoRoots\":[\"$BATS_TEST_TMPDIR/nope\",\"$R\"],\"scanDepth\":4}"
  run --separate-stderr "$DEVBAR" repos
  [ "$status" -eq 0 ]
  [ "$(jq length <<<"$output")" = 2 ]
  [[ "$stderr" == *nope* ]]
}

@test "repos: ~ espansa" {
  mkdir -p "$HOME/code/p"
  : >"$HOME/code/p/composer.lock"
  write_config '{"repoRoots":["~/code"]}'
  run --separate-stderr "$DEVBAR" repos
  [ "$(jq -r '.[0].path' <<<"$output")" = "$HOME/code/p" ]
}

@test "npm-audit: repoRoots vuoto -> rc 3" {
  write_config '{"repoRoots":[]}'
  run --separate-stderr "$DEVBAR" check npm-audit
  [ "$status" -eq 3 ]
  [ "$(jq -r .summary <<<"$output")" = "nessuna cartella repo configurata" ]
}

@test "npm-audit: 1 critical in a -> rc 0, count 1, eseguito nel repo" {
  export STUB_NPM_FIXTURE=audit-critical.json STUB_NPM_RC=1
  run --separate-stderr "$DEVBAR" check npm-audit
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" = 1 ]
  [ "$(jq -r '.items[0]|[.repo,.critical,.high,.moderate,.low]|join(",")' <<<"$output")" = "$R/a,1,3,2,1" ]
  grep -q 'audit --json' "$BATS_TEST_TMPDIR/npm.calls"
}

@test "npm-audit: nessuna vuln -> rc 1" {
  export STUB_NPM_FIXTURE=audit-clean.json
  run --separate-stderr "$DEVBAR" check npm-audit
  [ "$status" -eq 1 ]
}

@test "npm-audit: cache e --force" {
  export STUB_NPM_FIXTURE=audit-critical.json
  run --separate-stderr "$DEVBAR" check npm-audit
  run --separate-stderr "$DEVBAR" check npm-audit
  [ "$(wc -l <"$BATS_TEST_TMPDIR/npm.calls")" -eq 1 ]
  run --separate-stderr "$DEVBAR" check npm-audit --force
  [ "$(wc -l <"$BATS_TEST_TMPDIR/npm.calls")" -eq 2 ]
}

@test "npm-audit: fallimento in un repo non ferma gli altri" {
  mkdir -p "$R/z"; : >"$R/z/package-lock.json"
  rm -f "$BATS_TEST_TMPDIR/stubs/npm"
  cat >"$BATS_TEST_TMPDIR/stubs/npm" <<S
#!/usr/bin/env bash
case "\$PWD" in */z) echo "npm ERR! network" >&2; exit 1 ;; esac
cat "$DEVBAR_REPO/tests/fixtures/npm/audit-critical.json"; exit 1
S
  chmod +x "$BATS_TEST_TMPDIR/stubs/npm"
  run --separate-stderr "$DEVBAR" check npm-audit
  [ "$status" -eq 0 ]
  [ "$(jq -r '.items|length' <<<"$output")" = 2 ]
  [ "$(jq -r '.items[]|select(.repo|endswith("/z")).error' <<<"$output")" != null ]
  [ "$(jq -r '.items[]|select(.repo|endswith("/a")).critical' <<<"$output")" = 1 ]
}

@test "composer-audit: conteggi per severity" {
  export STUB_COMPOSER_FIXTURE=audit-high.json STUB_COMPOSER_RC=1
  run --separate-stderr "$DEVBAR" check composer-audit
  [ "$status" -eq 0 ]
  [ "$(jq -r '.items[0]|[.repo,.critical,.high,.moderate,.low]|join(",")' <<<"$output")" = "$R/b/c,1,1,1,1" ]
  grep -q 'audit --format=json --locked' "$BATS_TEST_TMPDIR/composer.calls"
}

@test "composer-audit: nessuna vuln -> rc 1" {
  export STUB_COMPOSER_FIXTURE=audit-clean.json
  run --separate-stderr "$DEVBAR" check composer-audit
  [ "$status" -eq 1 ]
}

@test "composer-audit: composer assente -> rc 3" {
  rm -f "$BATS_TEST_TMPDIR/stubs/composer"
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" "$(command -v bash)" "$DEVBAR" check composer-audit
  [ "$status" -eq 3 ]
}
