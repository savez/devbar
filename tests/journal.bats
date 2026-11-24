#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Registro delle modifiche (lib/journal.sh) e `devbar undo`. HOME temporanea: nessun file reale.

load helpers

setup() {
  setup_env
  make_stub rtk
  DEVBAR="$DEVBAR_REPO/bin/devbar"
  J="$HOME/.local/state/devbar/journal"
  CFG="$HOME/.config/caveman/config.json"
}

# entries: numero di voci nel registro.
entries() { find "$J" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
# last_id: id della voce più recente (da `devbar journal`).
last_id() { "$DEVBAR" journal | jq -r '.entries[0].id'; }

# Repo git con i tre hook tokensave e .tokensave/ già presenti: project-apply scrive solo le regole caveman.
ts_ready_repo() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/.tokensave"
  git -C "$REPO" init -q
  REPO="$(cd "$REPO" && pwd -P)"
  local h
  for h in post-checkout post-commit post-merge; do echo "# tokensave" >"$REPO/.git/hooks/$h"; done
}

# tokensave finto che scrive davvero (init: .tokensave/, info/exclude, hook).
writing_tokensave() {
  rm -f "$BATS_TEST_TMPDIR/stubs/tokensave"
  cat >"$BATS_TEST_TMPDIR/stubs/tokensave" <<'STUB'
#!/usr/bin/env bash
hooks="$(git rev-parse --git-path hooks)"
case "$1" in
  init)
    mkdir -p .tokensave "$hooks"
    echo db >.tokensave/index.db
    echo ".tokensave/" >>"$(git rev-parse --git-path info/exclude)"
    for h in post-checkout post-commit post-merge; do echo "# tokensave" >"$hooks/$h"; done ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/tokensave"
}

fake_caveman_repo() {
  local c="$HOME/.cache/devbar/caveman"
  mkdir -p "$c/.git" "$c/installer" "$c/skills/caveman" "$c/src/rules"
  echo 'js' >"$c/installer/install.js"
  echo 'skill' >"$c/skills/caveman/SKILL.md"
  printf 'regola caveman\n' >"$c/src/rules/caveman-activate.md"
}

# --- registrazione ---

@test "journal: scrittura registrata con backup, sha prima/dopo e comando" {
  mkdir -p "$(dirname "$CFG")"
  printf '{"defaultMode":"full","x":1}' >"$CFG"
  before="$(shasum -a 256 "$CFG" | cut -d' ' -f1)"
  run --separate-stderr "$DEVBAR" run caveman-mode megacave --yes
  [ "$status" -eq 0 ]
  [ "$(entries)" -eq 1 ]
  run --separate-stderr "$DEVBAR" journal
  [ "$status" -eq 0 ]
  [ "$(jq '.entries | length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.entries[0].command' <<<"$output")" = "run caveman-mode megacave --yes" ]
  [ "$(jq -r '.entries[0].files[0].path' <<<"$output")" = "$CFG" ]
  [ "$(jq -r '.entries[0].files[0].existed' <<<"$output")" = true ]
  [ "$(jq -r '.entries[0].files[0].sha256Before' <<<"$output")" = "$before" ]
  [ "$(jq -r '.entries[0].files[0].sha256After' <<<"$output")" = "$(shasum -a 256 "$CFG" | cut -d' ' -f1)" ]
  [ "$(jq -r '.entries[0].files[0] | has("changed")' <<<"$output")" = false ]
  [ "$(jq -r '.entries[0].undone' <<<"$output")" = false ]
  # meta.json e copia del file com'era
  d="$(find "$J" -mindepth 1 -maxdepth 1 -type d)"
  [ -f "$d/meta.json" ]
  [ "$(jq -r .id "$d/meta.json")" = "$(jq -r '.entries[0].id' <<<"$output")" ]
  [[ "$(basename "$d")" == *-"$(jq -r .id "$d/meta.json")" ]]
  b="$(jq -r '.files[0].backup' "$d/meta.json")"
  cmp "$d/$b" <(printf '{"defaultMode":"full","x":1}')
}

@test "journal: config e cache di devbar non vengono registrati" {
  run --separate-stderr "$DEVBAR" run brew-exclude wget
  [ "$status" -eq 0 ]
  [ "$(entries)" -eq 0 ]
  # caveman-mode off scrive anche cavemanLastMode nel config devbar: solo il file caveman entra
  mkdir -p "$(dirname "$CFG")"
  echo '{"defaultMode":"ultracave"}' >"$CFG"
  "$DEVBAR" run caveman-mode off --yes >/dev/null 2>&1
  [ "$(jq -r .cavemanLastMode "$DEVBAR_CONFIG")" = ultracave ]
  [ "$("$DEVBAR" journal | jq '.entries[0].files | length')" -eq 1 ]
  [ "$("$DEVBAR" journal | jq -r '.entries[0].files[0].path')" = "$CFG" ]
}

@test "journal: piano senza --yes e scrittura identica non creano voci" {
  "$DEVBAR" run caveman-mode megacave >/dev/null 2>&1
  [ "$(entries)" -eq 0 ]
  mkdir -p "$(dirname "$CFG")"
  printf '{\n  "defaultMode": "megacave"\n}\n' >"$CFG"
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  [ "$(entries)" -eq 0 ]
}

@test "journal: una sola voce per invocazione, anche con più file e scritture in pipeline" {
  ts_ready_repo
  printf 'testo utente senza a capo' >"$REPO/AGENTS.md"
  run --separate-stderr "$DEVBAR" run project-apply "$REPO" --yes
  [ "$status" -eq 0 ]
  [ "$(entries)" -eq 1 ]
  [ "$("$DEVBAR" journal | jq '.entries[0].files | length')" -eq 6 ]
}

@test "journal: tiene le ultime 50 voci" {
  local i
  mkdir -p "$J"
  for i in $(seq 1 50); do
    mkdir -p "$J/20200101T0000$(printf '%02d' $((i % 60)))Z-old$i"
    jq -n --arg id "old$i" '{id:$id,time:"2020-01-01T00:00:00Z",command:"run x",files:[]}' >"$J/20200101T0000$(printf '%02d' $((i % 60)))Z-old$i/meta.json"
  done
  [ "$(entries)" -eq 50 ]
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  [ "$(entries)" -eq 50 ]
  [ ! -d "$J/20200101T000001Z-old1" ]
  [ -d "$J/20200101T000002Z-old2" ]
  [ "$("$DEVBAR" journal | jq -r '.entries[0].command')" = "run caveman-mode megacave --yes" ]
}

@test "journal --limit N: solo le N voci più recenti; limite non valido -> rc 2" {
  local i
  for i in 1 2 3; do
    mkdir -p "$J/2020010${i}T000000Z-v$i"
    jq -n --arg id "v$i" '{id:$id,time:"2020-01-01T00:00:00Z",command:"run x",files:[]}' >"$J/2020010${i}T000000Z-v$i/meta.json"
  done
  run --separate-stderr "$DEVBAR" journal --limit 2
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.entries[].id] | join(",")' <<<"$output")" = "v3,v2" ]
  run --separate-stderr "$DEVBAR" journal --limit x
  [ "$status" -eq 2 ]
}

# --- undo ---

@test "undo: senza --yes stampa il piano e non tocca nulla" {
  mkdir -p "$(dirname "$CFG")"
  printf '{"defaultMode":"full"}' >"$CFG"
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  after="$(cat "$CFG")"
  run --separate-stderr "$DEVBAR" undo
  [ "$status" -eq 0 ]
  [ "$(jq -r .plan <<<"$output")" = true ]
  [ "$(jq -r .id <<<"$output")" = "$(last_id)" ]
  [ "$(jq -r '.commands | length' <<<"$output")" -ge 1 ]
  [ "$(jq -r '.files[0].action' <<<"$output")" = restore ]
  [ "$(jq -r .needsForce <<<"$output")" = false ]
  [ "$(cat "$CFG")" = "$after" ]
}

@test "undo --yes: ripristina byte per byte (file senza a capo finale, modo preservato)" {
  mkdir -p "$(dirname "$CFG")"
  printf '{"defaultMode":"full","x":1}' >"$CFG"
  chmod 600 "$CFG"
  cp -p "$CFG" "$BATS_TEST_TMPDIR/orig"
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  ! cmp -s "$CFG" "$BATS_TEST_TMPDIR/orig" || false
  run --separate-stderr "$DEVBAR" undo "$(last_id)" --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r .applied <<<"$output")" = true ]
  cmp "$CFG" "$BATS_TEST_TMPDIR/orig"
  [ "$(stat -f '%Lp' "$CFG")" = 600 ]
  [ "$("$DEVBAR" journal | jq -r '.entries[0].undone')" = true ]
}

@test "undo --yes: file creato da devbar viene rimosso" {
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  [ -f "$CFG" ]
  [ "$("$DEVBAR" journal | jq -r '.entries[0].files[0].existed')" = false ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  [ ! -e "$CFG" ]
}

@test "undo: voce con più file (project-apply) ripristina tutto, in pipeline e senza a capo" {
  ts_ready_repo
  printf 'testo utente senza a capo' >"$REPO/AGENTS.md"
  cp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/agents.orig"
  "$DEVBAR" run project-apply "$REPO" --yes >/dev/null 2>&1
  [ -f "$REPO/.cursor/rules/caveman.mdc" ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  cmp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/agents.orig"
  [ ! -e "$REPO/.cursor/rules/caveman.mdc" ]
  [ ! -e "$REPO/.clinerules/caveman.md" ]
}

@test "undo: file cambiato da un altro programma -> piano lo segnala, --yes non scrive nulla" {
  ts_ready_repo
  printf 'utente\n' >"$REPO/AGENTS.md"
  "$DEVBAR" run project-apply "$REPO" --yes >/dev/null 2>&1
  printf 'altro programma\n' >>"$REPO/AGENTS.md"
  cp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/agents.now"
  run --separate-stderr "$DEVBAR" undo
  [ "$status" -eq 0 ]
  [ "$(jq -r .needsForce <<<"$output")" = true ]
  [ "$(jq -r --arg p "$REPO/AGENTS.md" '.files[] | select(.path == $p) | .changed' <<<"$output")" = true ]
  [[ "$(jq -r '.commands | join("\n")' <<<"$output")" == *"cambiato"* ]]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 2 ]
  [ "$(jq -r .status <<<"$output")" = error ]
  [[ "$(jq -r .error <<<"$output")" == *"--force"* ]]
  # niente toccato: né il file cambiato né gli altri della stessa voce
  cmp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/agents.now"
  [ -f "$REPO/.cursor/rules/caveman.mdc" ]
  [ "$("$DEVBAR" journal | jq -r '.entries[0].undone')" = false ]
  # con --force si ripristina; la versione dell'altro programma resta accanto, non cancellata
  run --separate-stderr "$DEVBAR" undo --force --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/AGENTS.md")" = utente ]
  [ ! -e "$REPO/.cursor/rules/caveman.mdc" ]
  kept="$(jq -r '.kept[0]' <<<"$output")"
  d="$(find "$J" -mindepth 1 -maxdepth 1 -type d)"
  # conservata nella voce del registro, non accanto all'originale (sarebbe un file non tracciato)
  [ "$kept" = "$d/kept$REPO/AGENTS.md" ]
  cmp "$kept" "$BATS_TEST_TMPDIR/agents.now"
  [ -z "$(find "$REPO" -name '*.devbar-undo*')" ]
  [[ "$(jq -r '.commands | join("\n")' <<<"$output")" == *"resta in"*"/kept/"* ]]
}

@test "undo --force: cartella cambiata da un altro programma -> conservata nel registro, nessuna seconda skill" {
  make_stub git node
  fake_caveman_repo
  mkdir -p "$HOME/.agents/skills/caveman"
  echo vecchia >"$HOME/.agents/skills/caveman/SKILL.md"
  "$DEVBAR" run ai-install caveman copilot --yes >/dev/null 2>&1
  echo altro >"$HOME/.agents/skills/caveman/SKILL.md"
  run --separate-stderr "$DEVBAR" undo
  [ "$(jq -r .needsForce <<<"$output")" = true ]
  [[ "$(jq -r '.commands | join("\n")' <<<"$output")" == *"/kept/"* ]]
  run --separate-stderr "$DEVBAR" undo --force --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.agents/skills/caveman/SKILL.md")" = vecchia ]
  # una sola skill in skills/: la versione dell'altro programma è nella voce
  [ "$(find "$HOME/.agents/skills" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 1 ]
  kept="$(jq -r --arg p "$HOME/.agents/skills/caveman" '.kept[] | select(endswith($p))' <<<"$output")"
  d="$(find "$J" -mindepth 1 -maxdepth 1 -type d)"
  [ "$kept" = "$d/kept$HOME/.agents/skills/caveman" ]
  [ "$(cat "$kept/SKILL.md")" = altro ]
}

@test "undo: ripristino fallito -> backup intatto, voce non annullata; poi riprova" {
  mkdir -p "$(dirname "$CFG")"
  printf '{"a":1}' >"$CFG"
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  d="$(find "$J" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
  b="$d/$(jq -r '.files[0].backup' "$d/meta.json")"
  chmod 500 "$(dirname "$CFG")"
  run --separate-stderr "$DEVBAR" undo --yes
  chmod 700 "$(dirname "$CFG")"
  [ "$status" -eq 2 ]
  [ -f "$b" ]
  cmp "$b" <(printf '{"a":1}')
  [ "$(jq -r '.undoneAt // "no"' "$d/meta.json")" = no ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$CFG")" = '{"a":1}' ]
  [ -f "$b" ]
}

@test "undo: file già ripristinato a mano non è un conflitto" {
  mkdir -p "$(dirname "$CFG")"
  printf '{"a":1}' >"$CFG"
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  printf '{"a":1}' >"$CFG"
  run --separate-stderr "$DEVBAR" undo
  [ "$(jq -r .needsForce <<<"$output")" = false ]
  [ "$(jq -r '.files[0].action' <<<"$output")" = none ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
}

@test "undo: voce già annullata, id sconosciuto o non valido -> rc 2" {
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  "$DEVBAR" undo --yes >/dev/null
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 2 ]
  run --separate-stderr "$DEVBAR" undo nonce --yes
  [ "$status" -eq 2 ]
  run --separate-stderr "$DEVBAR" undo ../x --yes
  [ "$status" -eq 2 ]
  [ "$(jq -r .status <<<"$output")" = error ]
}

@test "undo: registro vuoto -> rc 2; journal vuoto -> lista vuota" {
  run --separate-stderr "$DEVBAR" journal
  [ "$status" -eq 0 ]
  [ "$(jq '.entries | length' <<<"$output")" -eq 0 ]
  run --separate-stderr "$DEVBAR" undo
  [ "$status" -eq 2 ]
}

@test "undo: un undo non crea a sua volta una voce" {
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  "$DEVBAR" undo --yes >/dev/null
  [ "$(entries)" -eq 1 ]
}

# --- strumenti esterni, cartelle, link, rimozioni ---

@test "journal: tokensave init -> .tokensave/ e hook creati vengono rimossi, info/exclude ripristinato" {
  writing_tokensave
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  REPO="$(cd "$REPO" && pwd -P)"
  printf 'mio\n' >"$REPO/.git/info/exclude"
  run --separate-stderr "$DEVBAR" run project-apply "$REPO" --yes
  [ "$status" -eq 0 ]
  [ -d "$REPO/.tokensave" ]
  [ -f "$REPO/.git/hooks/post-commit" ]
  run --separate-stderr "$DEVBAR" journal
  [ "$(jq -r --arg p "$REPO/.tokensave" '.entries[0].files[] | select(.path == $p) | .kind' <<<"$output")" = dir ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  [ ! -e "$REPO/.tokensave" ]
  [ ! -e "$REPO/.git/hooks/post-commit" ]
  [ "$(cat "$REPO/.git/info/exclude")" = mio ]
  [ ! -e "$REPO/AGENTS.md" ]
}

@test "journal: caveman copilot -> skill, link e cartella sostituita tornano com'erano" {
  make_stub git node
  fake_caveman_repo
  mkdir -p "$HOME/.agents/skills/caveman" "$HOME/.claude/skills/caveman"
  echo vecchia >"$HOME/.agents/skills/caveman/SKILL.md"
  echo mia >"$HOME/.claude/skills/caveman/NOTE.md"
  run --separate-stderr "$DEVBAR" run ai-install caveman copilot --yes
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/skills/caveman" ]
  [ "$(cat "$HOME/.agents/skills/caveman/SKILL.md")" = skill ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.agents/skills/caveman/SKILL.md")" = vecchia ]
  [ ! -L "$HOME/.claude/skills/caveman" ]
  [ "$(cat "$HOME/.claude/skills/caveman/NOTE.md")" = mia ]
  [ ! -e "$HOME/.copilot/skills/caveman" ]
  [ ! -L "$HOME/.copilot/skills/caveman" ]
  [ ! -e "$HOME/.copilot/copilot-instructions.md" ]
  [ -z "$(find "$HOME/.agents/skills" "$HOME/.claude/skills" -name '*.devbar-*')" ]
}

@test "journal: agent cavecrew rimosso da caveman opencode torna con undo" {
  make_stub git node
  fake_caveman_repo
  mkdir -p "$HOME/.config/opencode/agents"
  echo x >"$HOME/.config/opencode/agents/cavecrew-builder.md"
  "$DEVBAR" run ai-install caveman opencode --yes >/dev/null 2>&1
  [ ! -e "$HOME/.config/opencode/agents/cavecrew-builder.md" ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/opencode/agents/cavecrew-builder.md")" = x ]
}

@test "journal: rtk copilot -> rtk-run e istruzioni rimossi con undo" {
  run --separate-stderr "$DEVBAR" run ai-install rtk copilot --yes
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/rtk-run" ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/rtk-run" ]
  [ ! -e "$HOME/.copilot/copilot-instructions.md" ]
}

@test "journal: rtk scrive attraverso un symlink (dotfiles) -> undo ripristina il target, il link resta" {
  rm -f "$BATS_TEST_TMPDIR/stubs/rtk"
  cat >"$BATS_TEST_TMPDIR/stubs/rtk" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "init -g --auto-patch") printf '{"hooks":"rtk"}\n' >"$HOME/.claude/settings.json" ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/rtk"
  mkdir -p "$HOME/dotfiles" "$HOME/.claude"
  printf '{"mine":true}' >"$HOME/dotfiles/settings.json"
  ln -s "$HOME/dotfiles/settings.json" "$HOME/.claude/settings.json"
  run --separate-stderr "$DEVBAR" run ai-install rtk claude --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r .hooks "$HOME/dotfiles/settings.json")" = rtk ]
  [ "$("$DEVBAR" journal | jq -r --arg p "$HOME/dotfiles/settings.json" '[.entries[0].files[].path] | index($p) != null')" = true ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/settings.json" ]
  [ "$(readlink "$HOME/.claude/settings.json")" = "$HOME/dotfiles/settings.json" ]
  [ "$(cat "$HOME/dotfiles/settings.json")" = '{"mine":true}' ]
}

@test "journal: tokensave install registra i file noti dell'agente; il piano lo dice" {
  run --separate-stderr "$DEVBAR" run ai-install tokensave claude
  [ "$status" -eq 0 ]
  cmds="$(jq -r '.commands | join("\n")' <<<"$output")"
  [[ "$cmds" == *"annullabile"*"~/.claude/rules/tokensave.md"* ]]
  # ~/.claude.json: riscritto da Claude Code a ogni sessione, mai registrato; il piano lo dice
  [[ "$(grep annullabile <<<"$cmds")" != *".claude.json"* ]]
  [[ "$cmds" == *"non si può annullare da devbar per ~/.claude.json"* ]]
  rm -f "$BATS_TEST_TMPDIR/stubs/tokensave"
  cat >"$BATS_TEST_TMPDIR/stubs/tokensave" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  install) printf '{"mcpServers":{"tokensave":{}}}\n' >"$HOME/.claude.json"
    mkdir -p "$HOME/.claude/rules"; echo regole >"$HOME/.claude/rules/tokensave.md" ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/tokensave"
  printf '{"numStartups":3}' >"$HOME/.claude.json"
  run --separate-stderr "$DEVBAR" run ai-install tokensave claude --yes
  [ "$status" -eq 0 ]
  [ "$("$DEVBAR" journal | jq -r --arg p "$HOME/.claude.json" '[.entries[0].files[].path] | index($p)')" = null ]
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude.json")" = '{"mcpServers":{"tokensave":{}}}' ]
  [ ! -e "$HOME/.claude/rules/tokensave.md" ]
}

# mv che registra le chiamate; con MV_FAIL fallisce quando la sorgente contiene quel testo.
logging_mv() {
  cat >"$BATS_TEST_TMPDIR/stubs/mv" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$BATS_TEST_TMPDIR/mv.calls"
if [ -n "${MV_FAIL:-}" ]; then
  case "$1" in *"$MV_FAIL"*) exit 1 ;; esac
fi
exec /bin/mv "$@"
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/mv"
}

@test "undo: prima i ripristini, poi le rimozioni (il backup .devbar-<data> sparisce per ultimo)" {
  make_stub git node
  fake_caveman_repo
  mkdir -p "$HOME/.agents/skills/caveman"
  echo vecchia >"$HOME/.agents/skills/caveman/SKILL.md"
  "$DEVBAR" run ai-install caveman copilot --yes >/dev/null 2>&1
  logging_mv
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  # riga del ripristino della skill (tmp -> skill) prima dello spostamento del backup .devbar-
  restore="$(grep -n "/.devbar-undo\.[^ ]*/caveman $HOME/.agents/skills/caveman\$" "$BATS_TEST_TMPDIR/mv.calls" | cut -d: -f1)"
  remove="$(grep -n "^$HOME/.agents/skills/caveman\.devbar-" "$BATS_TEST_TMPDIR/mv.calls" | cut -d: -f1)"
  [ -n "$restore" ]
  [ -n "$remove" ]
  [ "$restore" -lt "$remove" ]
  [ "$(cat "$HOME/.agents/skills/caveman/SKILL.md")" = vecchia ]
}

@test "undo: spostato da parte, passo finale fallito -> torna com'era, voce non annullata" {
  mkdir -p "$(dirname "$CFG")"
  printf '{"a":1}' >"$CFG"
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  cp "$CFG" "$BATS_TEST_TMPDIR/after"
  logging_mv
  MV_FAIL=/.devbar-undo. run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 2 ]
  # lo spostamento da parte c'è stato, ed è stato annullato
  grep -q "^$CFG .*/.devbar-undo-old\." "$BATS_TEST_TMPDIR/mv.calls"
  cmp "$CFG" "$BATS_TEST_TMPDIR/after"
  [ -z "$(find "$(dirname "$CFG")" -name '.devbar-undo*')" ]
  [ "$("$DEVBAR" journal | jq -r '.entries[0].undone')" = false ]
  rm -f "$BATS_TEST_TMPDIR/stubs/mv"
  run --separate-stderr "$DEVBAR" undo --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$CFG")" = '{"a":1}' ]
}

@test "undo: file illeggibile -> trattato come cambiato (serve --force), mai come assente" {
  "$DEVBAR" run caveman-mode megacave --yes >/dev/null 2>&1
  chmod 000 "$CFG"
  run --separate-stderr "$DEVBAR" undo
  chmod 600 "$CFG"
  [ "$status" -eq 0 ]
  [ "$(jq -r .needsForce <<<"$output")" = true ]
  [ "$(jq -r '.files[0].action' <<<"$output")" = remove ]
  chmod 000 "$CFG"
  run --separate-stderr "$DEVBAR" undo --yes
  chmod 600 "$CFG"
  [ "$status" -eq 2 ]
  [ -f "$CFG" ]
}

@test "journal: target illeggibile -> nessuna scrittura (backup impossibile)" {
  mkdir -p "$HOME/.copilot"
  printf 'mio' >"$HOME/.copilot/copilot-instructions.md"
  chmod 000 "$HOME/.copilot/copilot-instructions.md"
  run --separate-stderr "$DEVBAR" run ai-install rtk copilot --yes
  chmod 600 "$HOME/.copilot/copilot-instructions.md"
  [ "$status" -eq 2 ]
  [ "$(cat "$HOME/.copilot/copilot-instructions.md")" = mio ]
}
