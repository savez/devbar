#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub rtk tokensave
  DEVBAR="$DEVBAR_REPO/bin/devbar"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  # tokensave finto: init crea .tokensave e gli hook, githooks crea solo gli hook
  rm -f "$BATS_TEST_TMPDIR/stubs/tokensave"
  cat >"$BATS_TEST_TMPDIR/stubs/tokensave" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$BATS_TEST_TMPDIR/tokensave.calls"
hooks="$(git rev-parse --git-path hooks)"
case "$1" in
  init)
    mkdir -p .tokensave "$hooks" "$(dirname "$(git rev-parse --git-path info/exclude)")"
    echo ".tokensave/" >>"$(git rev-parse --git-path info/exclude)"
    for h in post-checkout post-commit post-merge; do echo "# tokensave" >"$hooks/$h"; done ;;
  githooks)
    mkdir -p "$hooks"
    for h in post-checkout post-commit post-merge; do echo "# tokensave" >"$hooks/$h"; done ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/tokensave"
}

@test "project-status repo vuoto: 3 check, caveman e tokensave non ok con willWrite" {
  run --separate-stderr "$DEVBAR" run project-status "$REPO"
  [ "$status" -eq 0 ]
  [ "$(jq '.checks | length' <<<"$output")" -eq 3 ]
  [ "$(jq -r '[.checks[].tool] | join(",")' <<<"$output")" = "rtk,caveman,tokensave" ]
  [ "$(jq -r '.checks[] | select(.tool=="caveman") | .ok' <<<"$output")" = false ]
  [ "$(jq -r '.checks[] | select(.tool=="caveman") | .willWrite | length' <<<"$output")" -gt 0 ]
  [ "$(jq -r '.checks[] | select(.tool=="tokensave") | .ok' <<<"$output")" = false ]
  [[ "$(jq -r '.checks[] | select(.tool=="tokensave") | .willWrite | join(" ")' <<<"$output")" == *".tokensave/"* ]]
  [ "$(jq -r '.path' <<<"$output")" = "$(cd "$REPO" && pwd -P)" ] || [ "$(jq -r '.path' <<<"$output")" = "$REPO" ]
}

@test "project-status rtk: ok con un harness installed" {
  export STUB_RTK_FIXTURE=show-all.txt
  run --separate-stderr "$DEVBAR" run project-status "$REPO"
  [ "$(jq -r '.checks[] | select(.tool=="rtk") | .ok' <<<"$output")" = true ]
}

@test "project-apply senza --yes: nessun file creato" {
  run --separate-stderr "$DEVBAR" run project-apply "$REPO"
  [ "$status" -eq 0 ]
  [ "$(jq '.checks | length' <<<"$output")" -eq 3 ]
  [ -z "$(git -C "$REPO" status --porcelain)" ]
  [ ! -e "$BATS_TEST_TMPDIR/tokensave.calls" ]
}

@test "project-apply --yes: tokensave init, regola caveman, stato ok" {
  run --separate-stderr "$DEVBAR" run project-apply "$REPO" --yes
  [ "$status" -eq 0 ]
  grep -q '^init --git-hook' "$BATS_TEST_TMPDIR/tokensave.calls"
  ! grep -q '^install' "$BATS_TEST_TMPDIR/tokensave.calls"
  grep -q 'Respond terse like smart caveman' "$REPO/.cursor/rules/caveman.mdc"
  grep -q 'alwaysApply: true' "$REPO/.cursor/rules/caveman.mdc"
  grep -q 'trigger: always_on' "$REPO/.windsurf/rules/caveman.md"
  grep -q 'Respond terse' "$REPO/.clinerules/caveman.md"
  grep -qx '<!-- caveman-begin -->' "$REPO/AGENTS.md"
  grep -qx '<!-- caveman-end -->' "$REPO/.github/copilot-instructions.md"
  [ -f "$REPO/.opencode/AGENTS.md" ]
  [ "$(jq -r '.checks[] | select(.tool=="caveman") | .ok' <<<"$output")" = true ]
  [ "$(jq -r '.checks[] | select(.tool=="tokensave") | .ok' <<<"$output")" = true ]
  [ -z "$(find "$REPO" -name '.devbar-write.*')" ]
}

@test "project-apply --yes due volte: nessuna nuova scrittura" {
  "$DEVBAR" run project-apply "$REPO" --yes >/dev/null 2>&1
  before="$(cd "$REPO" && find . -path ./.git -prune -o -type f -exec stat -f '%m %N' {} + | sort | md5)"
  cp "$BATS_TEST_TMPDIR/tokensave.calls" "$BATS_TEST_TMPDIR/calls1"
  sleep 1.1
  run --separate-stderr "$DEVBAR" run project-apply "$REPO" --yes
  [ "$status" -eq 0 ]
  after="$(cd "$REPO" && find . -path ./.git -prune -o -type f -exec stat -f '%m %N' {} + | sort | md5)"
  [ "$before" = "$after" ]
  cmp "$BATS_TEST_TMPDIR/tokensave.calls" "$BATS_TEST_TMPDIR/calls1"
}

@test "caveman: AGENTS.md esistente, blocco aggiunto in coda e contenuto utente intatto" {
  printf '# Mio\n\nregola mia\n' >"$REPO/AGENTS.md"
  "$DEVBAR" run project-apply "$REPO" --yes >/dev/null 2>&1
  [ "$(head -3 "$REPO/AGENTS.md")" = "$(printf '# Mio\n\nregola mia')" ]
  grep -qx '<!-- caveman-begin -->' "$REPO/AGENTS.md"
}

@test "caveman: blocco vecchio viene aggiornato, testo utente resta" {
  printf 'prima\n<!-- caveman-begin -->\nvecchio\n<!-- caveman-end -->\ndopo\n' >"$REPO/AGENTS.md"
  run --separate-stderr "$DEVBAR" run project-status "$REPO"
  [[ "$(jq -r '.checks[] | select(.tool=="caveman") | .willWrite | join(" ")' <<<"$output")" == *AGENTS.md* ]]
  "$DEVBAR" run project-apply "$REPO" --yes >/dev/null 2>&1
  ! grep -q vecchio "$REPO/AGENTS.md"
  grep -qx prima "$REPO/AGENTS.md"
  grep -qx dopo "$REPO/AGENTS.md"
  grep -q 'Respond terse' "$REPO/AGENTS.md"
}

@test "caveman: marcatori danneggiati e symlink non vengono toccati" {
  printf 'x\n<!-- caveman-begin -->\nrotto\n' >"$REPO/AGENTS.md"
  printf 'mio\n' >"$REPO/real.md"
  mkdir -p "$REPO/.github"
  ln -s ../real.md "$REPO/.github/copilot-instructions.md"
  "$DEVBAR" run project-apply "$REPO" --yes >/dev/null 2>&1
  [ "$(cat "$REPO/AGENTS.md")" = "$(printf 'x\n<!-- caveman-begin -->\nrotto')" ]
  [ "$(cat "$REPO/real.md")" = mio ]
  [ -L "$REPO/.github/copilot-instructions.md" ]
}

@test "tokensave: indice presente ma hook assente: solo githooks --local" {
  mkdir -p "$REPO/.tokensave"
  "$DEVBAR" run project-apply "$REPO" --yes >/dev/null 2>&1
  grep -q '^githooks on --local' "$BATS_TEST_TMPDIR/tokensave.calls"
  ! grep -q '^init' "$BATS_TEST_TMPDIR/tokensave.calls"
}

@test "dir non repo git: rc 2" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run "$DEVBAR" run project-status "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 2 ]
  [[ "$output" == *"non è un repo git"* ]]
  run "$DEVBAR" run project-apply "$BATS_TEST_TMPDIR/nope" --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"non è un repo git"* ]]
}

@test "tokensave willWrite copre ogni percorso scritto dallo stub (percorsi assoluti)" {
  run --separate-stderr "$DEVBAR" run project-status "$REPO"
  ww="$(jq -r '.checks[] | select(.tool=="tokensave") | .willWrite[]' <<<"$output")"
  while IFS= read -r p; do [[ "$p" == /* ]]; done <<<"$ww"
  "$DEVBAR" run project-apply "$REPO" --yes >/dev/null 2>&1
  root="$(git -C "$REPO" rev-parse --show-toplevel)"
  for rel in .git/hooks/post-checkout .git/hooks/post-commit .git/hooks/post-merge .git/info/exclude; do
    grep -qxF "$root/$rel" <<<"$ww"
  done
  grep -qxF "$root/.tokensave/" <<<"$ww"
}

@test "tokensave: un solo hook mancante -> nohook, willWrite elenca i tre hook" {
  mkdir -p "$REPO/.tokensave" "$REPO/.git/hooks"
  echo "# tokensave" >"$REPO/.git/hooks/post-commit"
  run --separate-stderr "$DEVBAR" run project-status "$REPO"
  [ "$(jq -r '.checks[] | select(.tool=="tokensave") | .ok' <<<"$output")" = false ]
  [ "$(jq -r '.checks[] | select(.tool=="tokensave") | .willWrite | length' <<<"$output")" -eq 3 ]
}
