#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub rtk tokensave brew
  DEVBAR="$DEVBAR_REPO/bin/devbar"
}

@test "ai-install rtk claude senza --yes: stampa i comandi, non esegue" {
  run --separate-stderr "$DEVBAR" run ai-install rtk claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"rtk init -g --auto-patch"* ]]
  [ "$(jq -r .tool <<<"$output")" = rtk ]
  [ ! -e "$BATS_TEST_TMPDIR/rtk.calls" ]
  [ ! -e "$DEVBAR_CONFIG" ]
}

@test "ai-install rtk claude --yes: esegue, config harnesses contiene claude" {
  write_config '{"terminal":"iTerm","harnesses":["codex"]}'
  export STUB_RTK_FIXTURE=show-all.txt
  run --separate-stderr "$DEVBAR" run ai-install rtk claude --yes
  [ "$status" -eq 0 ]
  grep -q "init -g --auto-patch" "$BATS_TEST_TMPDIR/rtk.calls"
  [ "$(jq -c .harnesses "$DEVBAR_CONFIG")" = '["codex","claude"]' ]
  [ "$(jq -r .terminal "$DEVBAR_CONFIG")" = iTerm ]
  # output = ai-status, un solo oggetto JSON
  [ "$(jq -r .tool <<<"$output")" = rtk ]
  [ "$(jq -r '.harnesses[]|select(.id=="claude").state' <<<"$output")" = installed ]
}

@test "ai-install --yes: dedupe, senza config parte da zero" {
  export STUB_RTK_FIXTURE=show-all.txt
  "$DEVBAR" run ai-install rtk claude --yes >/dev/null 2>&1
  "$DEVBAR" run ai-install rtk claude --yes >/dev/null 2>&1
  [ "$(jq -c .harnesses "$DEVBAR_CONFIG")" = '["claude"]' ]
}

@test "ai-install rtk fallito: rc 2, config invariata" {
  export STUB_RTK_INIT_RC=1
  run --separate-stderr "$DEVBAR" run ai-install rtk claude --yes
  [ "$status" -eq 2 ]
  [ "$(jq -r .status <<<"$output")" = error ]
  [ ! -e "$DEVBAR_CONFIG" ]
}

@test "ai-install rtk opencode/cursor: comandi" {
  run --separate-stderr "$DEVBAR" run ai-install rtk opencode cursor
  [[ "$output" == *"rtk init -g --opencode --auto-patch"* ]]
  [[ "$output" == *"rtk init -g --agent cursor"* ]]
}

@test "ai-install rtk gemini: harness non supportato, rc 2" {
  run --separate-stderr "$DEVBAR" run ai-install rtk gemini --yes
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/rtk.calls" ]
}

@test "ai-install: harness o tool non validi, rc 2" {
  run --separate-stderr "$DEVBAR" run ai-install rtk '../x' --yes
  [ "$status" -eq 2 ]
  run --separate-stderr "$DEVBAR" run ai-install nope claude --yes
  [ "$status" -eq 2 ]
  run --separate-stderr "$DEVBAR" run ai-install rtk
  [ "$status" -eq 2 ]
}

@test "ai-status rtk: stati da rtk init --show" {
  export STUB_RTK_FIXTURE=show-all.txt
  run --separate-stderr "$DEVBAR" run ai-status rtk
  [ "$status" -eq 0 ]
  [ "$(jq -r .installed <<<"$output")" = true ]
  [ "$(jq -r '.harnesses[]|select(.id=="claude").state' <<<"$output")" = installed ]
  [ "$(jq -r '.harnesses[]|select(.id=="opencode").state' <<<"$output")" = installed ]
  [ "$(jq -r '.harnesses[]|select(.id=="cursor").state' <<<"$output")" = missing ]
  [ "$(jq -r '.harnesses[]|select(.id=="gemini").state' <<<"$output")" = unsupported ]
  [ "$(jq -r '.harnesses[]|select(.id=="copilot").state' <<<"$output")" = missing ]
}

@test "ai-status rtk: nulla configurato -> missing" {
  export STUB_RTK_FIXTURE=show-none.txt
  run --separate-stderr "$DEVBAR" run ai-status rtk
  [ "$(jq -r '.harnesses[]|select(.id=="claude").state' <<<"$output")" = missing ]
  [ "$(jq -r '.harnesses[]|select(.id=="opencode").state' <<<"$output")" = missing ]
}

@test "ai-status rtk: copilot dal blocco istruzioni (installed/outdated)" {
  export STUB_RTK_FIXTURE=show-none.txt
  mkdir -p "$HOME/.copilot"
  bash -c "source '$DEVBAR_REPO/lib/common.sh'; source '$DEVBAR_REPO/lib/ai/rtk.sh'; _rtk_inject_with_markers '$HOME/.copilot/copilot-instructions.md' \"\$(_rtk_copilot_instructions)\""
  run --separate-stderr "$DEVBAR" run ai-status rtk
  [ "$(jq -r '.harnesses[]|select(.id=="copilot").state' <<<"$output")" = installed ]
  sed -i '' 's/high-output/old-output/' "$HOME/.copilot/copilot-instructions.md"
  run --separate-stderr "$DEVBAR" run ai-status rtk
  [ "$(jq -r '.harnesses[]|select(.id=="copilot").state' <<<"$output")" = outdated ]
}

@test "ai-install rtk copilot --yes: blocco + rtk-run, idempotente, preserva il resto" {
  mkdir -p "$HOME/.copilot"
  printf 'mio testo\n' >"$HOME/.copilot/copilot-instructions.md"
  "$DEVBAR" run ai-install rtk copilot --yes >/dev/null 2>&1
  "$DEVBAR" run ai-install rtk copilot --yes >/dev/null 2>&1
  f="$HOME/.copilot/copilot-instructions.md"
  grep -q "mio testo" "$f"
  [ "$(grep -c 'BEGIN RTK MANAGED BLOCK' "$f")" = 1 ]
  grep -q 'rtk-run' "$f"
  [ -x "$HOME/.local/bin/rtk-run" ]
  run grep -q "init -g" "$BATS_TEST_TMPDIR/rtk.calls"
  [ "$status" -ne 0 ]
}

@test "ai-install rtk copilot: symlink non toccato" {
  mkdir -p "$HOME/.copilot" "$HOME/elsewhere"
  echo orig >"$HOME/elsewhere/i.md"
  ln -s "$HOME/elsewhere/i.md" "$HOME/.copilot/copilot-instructions.md"
  "$DEVBAR" run ai-install rtk copilot --yes >/dev/null 2>&1
  [ "$(cat "$HOME/elsewhere/i.md")" = orig ]
}

@test "patch plugin OpenCode 2.x: applicata solo se opencode >= 2" {
  mkdir -p "$HOME/.config/opencode/plugins" "$BATS_TEST_TMPDIR/stubs"
  echo "v1 plugin" >"$HOME/.config/opencode/plugins/rtk.ts"
  printf '#!/bin/sh\necho "opencode v1.4.2"\n' >"$BATS_TEST_TMPDIR/stubs/opencode"
  chmod +x "$BATS_TEST_TMPDIR/stubs/opencode"
  "$DEVBAR" run ai-install rtk opencode --yes >/dev/null 2>&1
  [ "$(cat "$HOME/.config/opencode/plugins/rtk.ts")" = "v1 plugin" ]
  printf '#!/bin/sh\necho "opencode v2.0.5"\n' >"$BATS_TEST_TMPDIR/stubs/opencode"
  "$DEVBAR" run ai-install rtk opencode --yes >/dev/null 2>&1
  cmp "$DEVBAR_REPO/lib/ai/patches/opencode-plugin.ts" "$HOME/.config/opencode/plugins/rtk.ts"
}

@test "ai-status rtk opencode 2.x: plugin diverso dalla patch -> outdated" {
  export STUB_RTK_FIXTURE=show-all.txt
  mkdir -p "$HOME/.config/opencode/plugins"
  echo "v1 plugin" >"$HOME/.config/opencode/plugins/rtk.ts"
  printf '#!/bin/sh\necho "opencode v2.0.5"\n' >"$BATS_TEST_TMPDIR/stubs/opencode"
  chmod +x "$BATS_TEST_TMPDIR/stubs/opencode"
  run --separate-stderr "$DEVBAR" run ai-status rtk
  [ "$(jq -r '.harnesses[]|select(.id=="opencode").state' <<<"$output")" = outdated ]
}

@test "ai-status rtk assente: installed false" {
  rm -f "$BATS_TEST_TMPDIR/stubs/rtk"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -sf "$(command -v jq)" "$BATS_TEST_TMPDIR/bin/jq"
  PATH="$BATS_TEST_TMPDIR/stubs:$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run --separate-stderr "$DEVBAR" run ai-status rtk
  [ "$status" -eq 0 ]
  [ "$(jq -r .installed <<<"$output")" = false ]
}

@test "ai-install tokensave claude opencode --yes: una chiamata con due --agent" {
  run --separate-stderr "$DEVBAR" run ai-install tokensave claude opencode --yes
  [ "$status" -eq 0 ]
  grep -q "install --agent claude --agent opencode" "$BATS_TEST_TMPDIR/tokensave.calls"
  [ "$(jq -c .harnesses "$DEVBAR_CONFIG")" = '["claude","opencode"]' ]
  [ "$(jq -r .tool <<<"$output")" = tokensave ]
}

@test "ai-install tokensave senza --yes: solo piano" {
  run --separate-stderr "$DEVBAR" run ai-install tokensave claude
  [[ "$output" == *"tokensave install --agent claude"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/tokensave.calls" ]
}

@test "ai-status tokensave: ok / mancante / parziale da doctor" {
  export STUB_TOKENSAVE_DOCTOR_FIXTURE=doctor-claude-ok.txt
  run --separate-stderr "$DEVBAR" run ai-status tokensave
  [ "$(jq -r '.harnesses[]|select(.id=="claude").state' <<<"$output")" = installed ]
  export STUB_TOKENSAVE_DOCTOR_FIXTURE=doctor-cursor-missing.txt
  run --separate-stderr "$DEVBAR" run ai-status tokensave
  [ "$(jq -r '.harnesses[]|select(.id=="cursor").state' <<<"$output")" = missing ]
  export STUB_TOKENSAVE_DOCTOR_FIXTURE=doctor-copilot-partial.txt
  run --separate-stderr "$DEVBAR" run ai-status tokensave
  [ "$(jq -r '.harnesses[]|select(.id=="copilot").state' <<<"$output")" = outdated ]
  grep -q "doctor --agent copilot" "$BATS_TEST_TMPDIR/tokensave.calls"
}

@test "tool-install: senza --yes stampa, con --yes esegue brew" {
  run --separate-stderr "$DEVBAR" run tool-install rtk
  [[ "$output" == *"brew install rtk-ai/tap/rtk"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/brew.calls" ]
  run --separate-stderr "$DEVBAR" run tool-install tokensave --yes
  [ "$status" -eq 0 ]
  grep -q "install aovestdipaperino/tap/tokensave" "$BATS_TEST_TMPDIR/brew.calls"
  run --separate-stderr "$DEVBAR" run tool-install caveman --yes
  [ "$status" -eq 2 ]
}

@test "ai-install rtk copilot: rtk-run symlink -> scritto sul file risolto, il link resta" {
  mkdir -p "$HOME/.local/bin" "$HOME/dotfiles"
  echo vecchio >"$HOME/dotfiles/rtk-run"
  ln -s "$HOME/dotfiles/rtk-run" "$HOME/.local/bin/rtk-run"
  "$DEVBAR" run ai-install rtk copilot --yes >/dev/null 2>&1
  [ -L "$HOME/.local/bin/rtk-run" ]
  cmp "$DEVBAR_REPO/lib/ai/rtk-run" "$HOME/dotfiles/rtk-run"
  [ -x "$HOME/dotfiles/rtk-run" ]
}

@test "ai-install rtk copilot: blocco orfano in ~/.github rimosso, resto intatto, nessun temp" {
  mkdir -p "$HOME/.github"
  printf 'mio\n<!-- BEGIN RTK MANAGED BLOCK -->\nx\n<!-- END RTK MANAGED BLOCK -->\n' >"$HOME/.github/copilot-instructions.md"
  "$DEVBAR" run ai-install rtk copilot --yes >/dev/null 2>&1
  [ "$(cat "$HOME/.github/copilot-instructions.md")" = mio ]
  [ -z "$(find "$HOME" -name '.devbar-write.*')" ]
}
