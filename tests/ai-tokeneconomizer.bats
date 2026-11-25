#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub claude codex copilot git
  DEVBAR="$DEVBAR_REPO/bin/devbar"
  CLONE="$BATS_TEST_TMPDIR/te-clone"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export DEVBAR_TE_DIR="$BATS_TEST_TMPDIR/default-clone"
}

make_clone() { # make_clone <dir>
  mkdir -p "$1/plugin/scripts"
  printf '#!/bin/sh\n' >"$1/plugin/scripts/te"
  chmod +x "$1/plugin/scripts/te"
}

marketplace() { # marketplace <dir>
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
  jq -nc --arg p "$1" '{tokeneconomizer:{source:{source:"directory",path:$p}}}' \
    >"$CLAUDE_CONFIG_DIR/plugins/known_marketplaces.json"
}

state_of() { jq -r --arg i "$1" '.harnesses[]|select(.id==$i).state' <<<"$output"; }

@test "te_clone_dir: legge il marketplace locale" {
  make_clone "$CLONE"; marketplace "$CLONE"
  run in_common "source '$DEVBAR_REPO/lib/ai/tokeneconomizer.sh'; te_clone_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "$CLONE" ]
}

@test "te_clone_dir: ripiego su DEVBAR_TE_DIR, poi rc 1" {
  run in_common "source '$DEVBAR_REPO/lib/ai/tokeneconomizer.sh'; te_clone_dir"
  [ "$status" -eq 1 ]
  make_clone "$DEVBAR_TE_DIR"
  run in_common "source '$DEVBAR_REPO/lib/ai/tokeneconomizer.sh'; te_clone_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEVBAR_TE_DIR" ]
}

@test "te_clone_dir: marketplace che punta a una cartella senza te, ripiego" {
  marketplace "$BATS_TEST_TMPDIR/vuota"; mkdir -p "$BATS_TEST_TMPDIR/vuota"
  make_clone "$DEVBAR_TE_DIR"
  run in_common "source '$DEVBAR_REPO/lib/ai/tokeneconomizer.sh'; te_clone_dir"
  [ "$output" = "$DEVBAR_TE_DIR" ]
}

@test "ai-status: harness non supportati" {
  make_clone "$CLONE"; marketplace "$CLONE"
  run --separate-stderr "$DEVBAR" run ai-status tokeneconomizer
  [ "$status" -eq 0 ]
  [ "$(jq -r .installed <<<"$output")" = true ]
  for h in opencode cursor gemini; do [ "$(state_of $h)" = unsupported ]; done
}

@test "ai-status: claude installed solo se il plugin è abilitato" {
  make_clone "$CLONE"; marketplace "$CLONE"
  export STUB_CLAUDE_PLUGIN_FIXTURE=plugins-te-enabled.json
  run --separate-stderr "$DEVBAR" run ai-status tokeneconomizer
  [ "$(state_of claude)" = installed ]
  export STUB_CLAUDE_PLUGIN_FIXTURE=plugins-te-disabled.json
  run --separate-stderr "$DEVBAR" run ai-status tokeneconomizer
  [ "$(state_of claude)" = missing ]
  export STUB_CLAUDE_PLUGIN_FIXTURE=plugins-none.json
  run --separate-stderr "$DEVBAR" run ai-status tokeneconomizer
  [ "$(state_of claude)" = missing ]
}

@test "ai-status: copilot e codex dal testo di plugin list" {
  make_clone "$CLONE"; marketplace "$CLONE"
  export STUB_COPILOT_PLUGIN_FIXTURE=plugins-te.txt STUB_CODEX_PLUGIN_FIXTURE=plugins-te.txt
  run --separate-stderr "$DEVBAR" run ai-status tokeneconomizer
  [ "$(state_of copilot)" = installed ]
  [ "$(state_of codex)" = installed ]
  export STUB_COPILOT_PLUGIN_FIXTURE=plugins-none.txt
  run --separate-stderr "$DEVBAR" run ai-status tokeneconomizer
  [ "$(state_of copilot)" = missing ]
}

@test "ai-status: CLI dell'harness mancante -> missing, rc 0" {
  make_clone "$CLONE"; marketplace "$CLONE"
  rm -f "$BATS_TEST_TMPDIR/stubs/codex"
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" "$(command -v bash)" "$DEVBAR" run ai-status tokeneconomizer
  [ "$status" -eq 0 ]
  [ "$(state_of codex)" = missing ]
}

@test "ai-status: senza clone -> installed false, tutti missing" {
  run --separate-stderr "$DEVBAR" run ai-status tokeneconomizer
  [ "$status" -eq 0 ]
  [ "$(jq -r .installed <<<"$output")" = false ]
  [ "$(state_of claude)" = missing ]
}

@test "tool-install senza --yes: piano con git clone, nessuna chiamata" {
  run --separate-stderr "$DEVBAR" run tool-install tokeneconomizer
  [ "$status" -eq 0 ]
  [ "$(jq -r '.commands[0]' <<<"$output")" = "git clone --depth 1 https://github.com/microsoft/TokenEconomizer.git $DEVBAR_TE_DIR" ]
  [ ! -e "$BATS_TEST_TMPDIR/git.calls" ]
}

@test "tool-install: clone già presente, il piano lo dice e --yes --here non clona" {
  make_clone "$CLONE"; marketplace "$CLONE"
  run --separate-stderr "$DEVBAR" run tool-install tokeneconomizer
  [[ "$(jq -r '.commands[0]' <<<"$output")" == *"già presente"* ]]
  run --separate-stderr "$DEVBAR" run tool-install tokeneconomizer --yes --here
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/git.calls" ]
}

@test "tool-install --yes --here: clona in DEVBAR_TE_DIR" {
  run --separate-stderr "$DEVBAR" run tool-install tokeneconomizer --yes --here
  grep -qx "clone --depth 1 https://github.com/microsoft/TokenEconomizer.git $DEVBAR_TE_DIR" "$BATS_TEST_TMPDIR/git.calls"
}

@test "ai-install claude --yes: marketplace add poi install" {
  make_clone "$CLONE"; marketplace "$CLONE"
  export STUB_CLAUDE_PLUGIN_FIXTURE=plugins-te-enabled.json
  run --separate-stderr "$DEVBAR" run ai-install tokeneconomizer claude --yes
  [ "$status" -eq 0 ]
  grep -qx "plugin marketplace add $CLONE" "$BATS_TEST_TMPDIR/claude.calls"
  grep -qx "plugin install tokeneconomizer@tokeneconomizer" "$BATS_TEST_TMPDIR/claude.calls"
  [ "$(jq -c .harnesses "$DEVBAR_CONFIG")" = '["claude"]' ]
}

@test "ai-install codex --yes: plugin add" {
  make_clone "$CLONE"; marketplace "$CLONE"
  run --separate-stderr "$DEVBAR" run ai-install tokeneconomizer codex --yes
  grep -qx "plugin marketplace add $CLONE" "$BATS_TEST_TMPDIR/codex.calls"
  grep -qx "plugin add tokeneconomizer@tokeneconomizer" "$BATS_TEST_TMPDIR/codex.calls"
}

@test "ai-install senza --yes: piano con avviso undo e passo manuale" {
  make_clone "$CLONE"; marketplace "$CLONE"
  run --separate-stderr "$DEVBAR" run ai-install tokeneconomizer claude copilot
  [ "$status" -eq 0 ]
  [[ "$output" == *"non si può annullare da devbar"* ]]
  [[ "$output" == *"/tokeneconomizer:toolprune refresh-catalog"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/claude.calls" ]
}

@test "ai-install: install che fallisce -> rc 2, config invariata" {
  make_clone "$CLONE"; marketplace "$CLONE"
  export STUB_CLAUDE_PLUGIN_RC=1
  run --separate-stderr "$DEVBAR" run ai-install tokeneconomizer claude --yes
  [ "$status" -eq 2 ]
  [ ! -e "$DEVBAR_CONFIG" ]
}

@test "ai-install senza clone: errore chiaro, nessuna chiamata" {
  run --separate-stderr "$DEVBAR" run ai-install tokeneconomizer claude --yes
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/claude.calls" ]
}
