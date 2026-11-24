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
  [ "$(jq -r '.entries[0].files[0].changed' <<<"$output")" = false ]
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
  run --separate-stderr "$DEVBAR" journal
  [ "$(jq -r --arg p "$REPO/AGENTS.md" '.entries[0].files[] | select(.path == $p) | .changed' <<<"$output")" = true ]
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
  # con --force si ripristina
  run --separate-stderr "$DEVBAR" undo --force --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/AGENTS.md")" = utente ]
  [ ! -e "$REPO/.cursor/rules/caveman.mdc" ]
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
  [ ! -e "$HOME/.copilot/skills/caveman" ] && [ ! -L "$HOME/.copilot/skills/caveman" ]
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
