#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub git node
  DEVBAR="$DEVBAR_REPO/bin/devbar"
  SETTINGS="$HOME/.claude/settings.json"
  SL="$DEVBAR_REPO/statusline/devbar-claude-statusline"
}

# stub claude: abilita il tool statusline
with_claude() {
  printf '#!/bin/sh\nexit 0\n' >"$BATS_TEST_TMPDIR/stubs/claude"
  chmod +x "$BATS_TEST_TMPDIR/stubs/claude"
}

# PATH senza claude (HOME è temporaneo: niente ~/.local/bin reale)
no_claude_path() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -sf "$(command -v jq)" "$BATS_TEST_TMPDIR/bin/jq"
  printf '%s' "$BATS_TEST_TMPDIR/stubs:$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
}

# --- statusline ---

@test "statusline senza --yes: piano, nessuna scrittura" {
  with_claude
  run --separate-stderr "$DEVBAR" run ai-install statusline claude
  [ "$status" -eq 0 ]
  [ "$(jq -r .plan <<<"$output")" = true ]
  [[ "$output" == *devbar-claude-statusline* ]]
  [ ! -e "$SETTINGS" ]
}

@test "statusline --yes: chiavi preservate, backup, comando devbar" {
  with_claude
  mkdir -p "$HOME/.claude"
  printf '{"model":"opus","hooks":{"a":[1]},"statusLine":{"type":"command","command":"old"}}\n' >"$SETTINGS"
  chmod 600 "$SETTINGS"
  run --separate-stderr "$DEVBAR" run ai-install statusline claude --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r .model "$SETTINGS")" = opus ]
  [ "$(jq -c .hooks "$SETTINGS")" = '{"a":[1]}' ]
  [ "$(jq -r .statusLine.type "$SETTINGS")" = command ]
  [ "$(jq -r .statusLine.command "$SETTINGS")" = "bash \"$DEVBAR_REPO/statusline/devbar-claude-statusline\"" ]
  run bash -c "ls '$HOME'/.claude/settings.json.devbar-* | wc -l"
  [ "$(tr -d ' ' <<<"$output")" = 1 ]
  [ "$(jq -r .statusLine.command "$HOME"/.claude/settings.json.devbar-*)" = old ]
  [ "$(stat -f %Lp "$SETTINGS")" = 600 ]
  run bash -c "ls -A '$HOME/.claude' | grep -c '^\.devbar-write' || true"
  [ "$output" = 0 ]
  # stato: installed
  run --separate-stderr "$DEVBAR" run ai-status statusline
  [ "$(jq -r '.harnesses[]|select(.id=="claude").state' <<<"$output")" = installed ]
  [ "$(jq -r '.harnesses[]|select(.id=="opencode").state' <<<"$output")" = unsupported ]
}

@test "statusline --yes: settings.json assente -> creato, nessun backup" {
  with_claude
  run --separate-stderr "$DEVBAR" run ai-install statusline claude --yes
  [ "$status" -eq 0 ]
  [[ "$(jq -r .statusLine.command "$SETTINGS")" == *devbar-claude-statusline* ]]
  run bash -c "ls '$HOME'/.claude/settings.json.devbar-* 2>/dev/null | wc -l"
  [ "$(tr -d ' ' <<<"$output")" = 0 ]
}

@test "statusline --yes: settings.json non valido -> rc 2, file intatto" {
  with_claude
  mkdir -p "$HOME/.claude"
  printf '{rotto' >"$SETTINGS"
  run --separate-stderr "$DEVBAR" run ai-install statusline claude --yes
  [ "$status" -eq 2 ]
  [ "$(cat "$SETTINGS")" = '{rotto' ]
  run bash -c "ls -A '$HOME/.claude'"
  [ "$output" = settings.json ]
}

@test "statusline --yes: symlink -> scrive sul file risolto, il link resta" {
  with_claude
  mkdir -p "$HOME/.claude" "$HOME/dot"
  echo '{"x":1}' >"$HOME/dot/settings.json"
  ln -s "$HOME/dot/settings.json" "$SETTINGS"
  "$DEVBAR" run ai-install statusline claude --yes >/dev/null 2>&1
  [ -L "$SETTINGS" ]
  [ "$(jq -r .x "$HOME/dot/settings.json")" = 1 ]
  [[ "$(jq -r .statusLine.command "$HOME/dot/settings.json")" == *devbar-claude-statusline* ]]
}

@test "ai-status statusline: stati missing/outdated" {
  with_claude
  run --separate-stderr "$DEVBAR" run ai-status statusline
  [ "$status" -eq 0 ]
  [ "$(jq -r '.harnesses[]|select(.id=="claude").state' <<<"$output")" = missing ]
  mkdir -p "$HOME/.claude"
  echo '{"statusLine":{"type":"command","command":"bash /altrove/sl"}}' >"$SETTINGS"
  run --separate-stderr "$DEVBAR" run ai-status statusline
  [ "$(jq -r '.harnesses[]|select(.id=="claude").state' <<<"$output")" = outdated ]
}

@test "ai-status statusline senza claude: rc 3" {
  PATH="$(no_claude_path)" run --separate-stderr "$DEVBAR" run ai-status statusline
  [ "$status" -eq 3 ]
  [ "$(jq -r .installed <<<"$output")" = false ]
}

@test "ai-install statusline opencode: non supportato, rc 2" {
  with_claude
  run --separate-stderr "$DEVBAR" run ai-install statusline opencode --yes
  [ "$status" -eq 2 ]
}

@test "statusline: stampa una riga dal fixture" {
  run env XDG_CACHE_HOME="$BATS_TEST_TMPDIR/xdg" bash "$SL" <"$DEVBAR_REPO/tests/fixtures/statusline/input.json"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 1 ]
  [[ "$output" == *"Opus 5"* ]]
  [[ "$output" == *"42%"* ]]
}

@test "devbar_write_file: mv fallito -> temp rimosso, originale intatto" {
  mkdir -p "$HOME/d"
  echo orig >"$HOME/d/f"
  printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/stubs/mv"
  chmod +x "$BATS_TEST_TMPDIR/stubs/mv"
  run in_common "echo nuovo | devbar_write_file '$HOME/d/f'"
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/d/f")" = orig ]
  run bash -c "ls -A '$HOME/d'"
  [ "$output" = f ]
}

# --- caveman ---

# repo caveman finto in cache (git è stub: il clone/fetch non fa nulla)
fake_caveman_repo() {
  local c="$HOME/.cache/devbar/caveman"
  mkdir -p "$c/.git" "$c/installer" "$c/skills/caveman" "$c/src/rules"
  echo 'js' >"$c/installer/install.js"
  echo 'skill' >"$c/skills/caveman/SKILL.md"
  printf 'regola caveman\n' >"$c/src/rules/caveman-activate.md"
}

@test "caveman senza --yes: piano, niente git/node" {
  run --separate-stderr "$DEVBAR" run ai-install caveman claude copilot
  [ "$status" -eq 0 ]
  [[ "$output" == *"git clone"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/git.calls" ]
  [ ! -e "$BATS_TEST_TMPDIR/node.calls" ]
  [ ! -e "$HOME/.config/caveman/config.json" ]
}

@test "caveman --yes: config esistente lite non toccato" {
  fake_caveman_repo
  mkdir -p "$HOME/.config/caveman"
  echo '{"defaultMode":"lite"}' >"$HOME/.config/caveman/config.json"
  run --separate-stderr "$DEVBAR" run ai-install caveman claude --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r .defaultMode "$HOME/.config/caveman/config.json")" = lite ]
  grep -q -- "--only claude --force --non-interactive --no-mcp-shrink" "$BATS_TEST_TMPDIR/node.calls"
  grep -q "fetch --depth=1 origin main" "$BATS_TEST_TMPDIR/git.calls"
}

@test "caveman --yes: config assente -> full" {
  fake_caveman_repo
  "$DEVBAR" run ai-install caveman claude --yes >/dev/null 2>&1
  [ "$(jq -r .defaultMode "$HOME/.config/caveman/config.json")" = full ]
}

@test "caveman --yes senza repo: clone (stub)" {
  "$DEVBAR" run ai-install caveman claude --yes >/dev/null 2>&1 || true
  grep -q "clone --depth=1 https://github.com/JuliusBrussee/caveman.git" "$BATS_TEST_TMPDIR/git.calls"
}

@test "caveman installer non trovato: rc 2" {
  mkdir -p "$HOME/.cache/devbar/caveman/.git"
  run --separate-stderr "$DEVBAR" run ai-install caveman claude --yes
  [ "$status" -eq 2 ]
}

@test "caveman copilot: skill, symlink, blocco idempotente, preserva il resto" {
  fake_caveman_repo
  mkdir -p "$HOME/.copilot"
  printf 'mio testo\n' >"$HOME/.copilot/copilot-instructions.md"
  "$DEVBAR" run ai-install caveman copilot --yes >/dev/null 2>&1
  run --separate-stderr "$DEVBAR" run ai-install caveman copilot --yes
  [ "$status" -eq 0 ]
  f="$HOME/.copilot/copilot-instructions.md"
  grep -q "mio testo" "$f"
  grep -q "regola caveman" "$f"
  [ "$(grep -c 'BEGIN CAVEMAN MANAGED BLOCK' "$f")" = 1 ]
  [ -f "$HOME/.agents/skills/caveman/SKILL.md" ]
  [ -L "$HOME/.copilot/skills/caveman" ]
  [ -L "$HOME/.claude/skills/caveman" ]
  [ "$(jq -r '.harnesses[]|select(.id=="copilot").state' <<<"$output")" = installed ]
  [ ! -e "$BATS_TEST_TMPDIR/node.calls" ]
}

@test "caveman copilot: symlink istruzioni non toccato" {
  fake_caveman_repo
  mkdir -p "$HOME/.copilot" "$HOME/elsewhere"
  echo orig >"$HOME/elsewhere/i.md"
  ln -s "$HOME/elsewhere/i.md" "$HOME/.copilot/copilot-instructions.md"
  "$DEVBAR" run ai-install caveman copilot --yes >/dev/null 2>&1
  [ "$(cat "$HOME/elsewhere/i.md")" = orig ]
}

@test "caveman opencode: agent incompatibili rimossi, plugin patchato" {
  fake_caveman_repo
  mkdir -p "$HOME/.config/opencode/agents" "$HOME/.config/opencode/plugins/caveman"
  echo x >"$HOME/.config/opencode/agents/cavecrew-builder.md"
  echo keep >"$HOME/.config/opencode/agents/altro.md"
  echo old >"$HOME/.config/opencode/plugins/caveman/plugin.js"
  "$DEVBAR" run ai-install caveman opencode --yes >/dev/null 2>&1
  [ ! -e "$HOME/.config/opencode/agents/cavecrew-builder.md" ]
  [ -e "$HOME/.config/opencode/agents/altro.md" ]
  cmp "$DEVBAR_REPO/lib/ai/patches/caveman-opencode-plugin.js" "$HOME/.config/opencode/plugins/caveman/plugin.js"
}

@test "ai-status caveman: claude/opencode/copilot da file" {
  run --separate-stderr "$DEVBAR" run ai-status caveman
  [ "$(jq -r '.harnesses[]|select(.id=="claude").state' <<<"$output")" = missing ]
  [ "$(jq -r '.harnesses[]|select(.id=="codex").state' <<<"$output")" = unsupported ]
  mkdir -p "$HOME/.claude/plugins/cache/caveman/caveman/1.0.0"
  run --separate-stderr "$DEVBAR" run ai-status caveman
  [ "$(jq -r '.harnesses[]|select(.id=="claude").state' <<<"$output")" = installed ]
}

# --- claude-usage ---

# curl finto: -sI -> redirect a tag; -o <file> <url> -> copia da $CU_DIR/<basename url>
make_curl() {
  cat >"$BATS_TEST_TMPDIR/stubs/curl" <<'SH'
#!/bin/bash
echo "$*" >>"$BATS_TEST_TMPDIR/curl.calls"
out="" url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -sI) head=1 ;;
    http*) url="$1" ;;
  esac
  shift
done
if [ -n "${head:-}" ]; then
  printf 'HTTP/2 302\r\nlocation: https://github.com/sparkfabrik/claude-usage/releases/tag/v1.2.3\r\n\r\n'
  exit 0
fi
cp "$CU_DIR/$(basename "$url")" "$out"
SH
  chmod +x "$BATS_TEST_TMPDIR/stubs/curl"
  export CU_DIR="$BATS_TEST_TMPDIR/cu"
  mkdir -p "$CU_DIR"
  printf '#!/bin/sh\necho "$CLAUDE_USAGE_VERSION" >"%s/ran"\n' "$BATS_TEST_TMPDIR" >"$CU_DIR/install.sh"
}

@test "tool-install claude-usage senza --yes: piano, niente rete" {
  make_curl
  run --separate-stderr "$DEVBAR" run tool-install claude-usage
  [ "$status" -eq 0 ]
  [ "$(jq -r .plan <<<"$output")" = true ]
  [ ! -e "$BATS_TEST_TMPDIR/curl.calls" ]
}

@test "tool-install claude-usage: checksum corretto -> esegue con la versione" {
  make_curl
  echo "$(shasum -a 256 "$CU_DIR/install.sh" | cut -d' ' -f1)  install.sh" >"$CU_DIR/checksums.txt"
  run --separate-stderr "$DEVBAR" run tool-install claude-usage --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/ran")" = v1.2.3 ]
  grep -q "releases/download/v1.2.3/install.sh" "$BATS_TEST_TMPDIR/curl.calls"
  grep -q "releases/download/v1.2.3/checksums.txt" "$BATS_TEST_TMPDIR/curl.calls"
  ! grep -q "api.github.com" "$BATS_TEST_TMPDIR/curl.calls"
}

@test "tool-install claude-usage: checksum sbagliato -> rc 2, install.sh non eseguito" {
  make_curl
  echo "$(printf 0%.0s {1..64})  install.sh" >"$CU_DIR/checksums.txt"
  run --separate-stderr "$DEVBAR" run tool-install claude-usage --yes
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "tool-install claude-usage: checksum assente nel file -> rc 2, non eseguito" {
  make_curl
  echo "abc  altro.tgz" >"$CU_DIR/checksums.txt"
  run --separate-stderr "$DEVBAR" run tool-install claude-usage --yes
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "tool-install claude-usage: redirect senza tag valido -> rc 2" {
  make_curl
  sed -i '' 's#tag/v1.2.3#tag/evil;rm#' "$BATS_TEST_TMPDIR/stubs/curl"
  run --separate-stderr "$DEVBAR" run tool-install claude-usage --yes
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}
