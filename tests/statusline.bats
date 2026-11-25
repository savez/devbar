#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

# Epoch dell'ultima risposta nei transcript finti: 2026-01-01T12:00:00Z.
T0=1767268800

setup() {
  setup_env
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  SL="$DEVBAR_REPO/statusline/devbar-claude-statusline"
  FX="$DEVBAR_REPO/tests/fixtures/statusline"
}

# render <transcript|-|none> <warm> <seen> <secondi dopo T0>
render() {
  local tr="$1" warm="$2" seen="$3" after="$4" tp
  case "$tr" in
    none) tp="" ;;
    missing) tp="$BATS_TEST_TMPDIR/nope.jsonl" ;;
    *) tp="$FX/$tr" ;;
  esac
  jq --arg tp "$tp" --argjson w "$warm" --argjson s "$seen" --arg sid "s$RANDOM$after" \
    '.prompt_cache={warm:$w,caching_observed:$s} | .session_id=$sid
     | if $tp=="" then . else .transcript_path=$tp end' "$FX/input.json" \
    | DEVBAR_STATUSLINE_NOW=$((T0 + after)) "$SL" | sed $'s/\x1b\\[[0-9;]*m//g'
}
# colore del segmento cache (raw)
raw() {
  jq --arg tp "$FX/$1" --arg sid "r$RANDOM" \
    '.prompt_cache={warm:true,caching_observed:true} | .session_id=$sid | .transcript_path=$tp' "$FX/input.json" \
    | DEVBAR_STATUSLINE_NOW=$((T0 + $2)) "$SL"
}

@test "1h calda a meta: minuti rimasti, verde" {
  run render transcript-1h.jsonl true true 780
  [[ "$output" == *"◷ 47m"* ]]
  run raw transcript-1h.jsonl 780
  [[ "$output" == *$'\033[38;5;114m◷ 47m'* ]]
}

@test "5m quasi scaduta: giallo" {
  run render transcript-5m.jsonl true true 240
  [[ "$output" == *"◷ 1m"* ]]
  run raw transcript-5m.jsonl 240
  [[ "$output" == *$'\033[38;5;178m◷ 1m'* ]]
}

@test "5m con piu di 20% rimasto: verde" {
  run raw transcript-5m.jsonl 100
  [[ "$output" == *$'\033[38;5;114m◷ 3m'* ]]
}

@test "sotto il minuto: <1m giallo" {
  run render transcript-5m.jsonl true true 270
  [[ "$output" == *"◷ <1m"* ]]
  run raw transcript-5m.jsonl 270
  [[ "$output" == *$'\033[38;5;178m◷ <1m'* ]]
}

@test "solo cache read: usa la TTL della risposta precedente (1h)" {
  run render transcript-1h-readonly.jsonl true true 780
  [[ "$output" == *"◷ 47m"* ]]
}

@test "nessuna info TTL: default 300s" {
  run render transcript-nottl.jsonl true true 100
  [[ "$output" == *"◷ 3m"* ]]
}

@test "fredda osservata: solo ❄" {
  run render transcript-1h.jsonl false true 780
  [[ "$output" == *"❄"* ]]
  [[ "$output" != *"◷"* ]]
}

@test "non osservata: niente" {
  run render transcript-1h.jsonl false false 780
  [[ "$output" != *"❄"* && "$output" != *"◷"* ]]
  run render transcript-1h.jsonl true false 780
  [[ "$output" != *"◷"* ]]
}

@test "transcript mancante o assente con cache calda: come oggi, niente minuti" {
  run render missing true true 780
  [[ "$output" != *"❄"* && ! "$output" =~ ◷ ]]
  run render none true true 780
  [[ "$output" != *"❄"* && ! "$output" =~ ◷ ]]
}

@test "calda ma scaduta secondo il calcolo: solo ◷" {
  run render transcript-5m.jsonl true true 400
  [[ "$output" == *"◷"* ]]
  [[ ! "$output" =~ ◷\ [0-9\<] ]]
}

@test "cache 5s: secondo render entro 5s non rilegge il transcript" {
  local sid=cachetest cp="$BATS_TEST_TMPDIR/tr.jsonl"
  cp "$FX/transcript-1h.jsonl" "$cp"
  go() { jq --arg tp "$cp" --arg sid "$sid" '.session_id=$sid|.transcript_path=$tp' "$FX/input.json" \
    | DEVBAR_STATUSLINE_NOW=$((T0 + $1)) "$SL" | sed $'s/\x1b\\[[0-9;]*m//g'; }
  run go 780; [[ "$output" == *"◷ 47m"* ]]
  : > "$cp"
  run go 782; [[ "$output" == *"◷ 46m"* ]]
  run go 790; [[ "$output" == *"◷"* && "$output" != *"◷ 4"* ]]
}

# --- caveman: flag per sessione (caveman 4.x) ---

# cave_render <session_id>: statusline senza ANSI per quella sessione.
cave_render() {
  jq --arg sid "$1" '.session_id=$sid | del(.transcript_path)' "$FX/input.json" \
    | DEVBAR_STATUSLINE_NOW=$T0 "$SL" | sed $'s/\x1b\\[[0-9;]*m//g'
}
cave_session() { # cave_session <id> <contenuto>
  mkdir -p "$HOME/.claude/.caveman-sessions"
  printf '%s\n' "$2" >"$HOME/.claude/.caveman-sessions/$1.mode"
}

@test "caveman: legge il flag della sessione (caveman 4.x)" {
  cave_session abc123 caveman
  run cave_render abc123
  [[ "$output" == *"CAVEMAN"* ]]
  [[ "$output" != *"CAVEMAN:"* ]]
}

@test "caveman: ultracave e megacave dal flag di sessione" {
  cave_session u1 ultracave; run cave_render u1; [[ "$output" == *"CAVEMAN:ULTRA"* ]]
  cave_session m1 megacave; run cave_render m1; [[ "$output" == *"CAVEMAN:WENYAN"* ]]
}

@test "caveman: off nella sessione vince sul flag globale" {
  cave_session s1 off
  mkdir -p "$HOME/.claude"; echo caveman >"$HOME/.claude/.caveman-active"
  run cave_render s1
  [[ "$output" != *"CAVEMAN"* ]]
}

@test "caveman: senza flag di sessione si usa il flag globale" {
  mkdir -p "$HOME/.claude"; echo ultracave >"$HOME/.claude/.caveman-active"
  run cave_render senza-file
  [[ "$output" == *"CAVEMAN:ULTRA"* ]]
}

@test "caveman: il flag di un'altra sessione non conta" {
  cave_session altra caveman
  run cave_render questa
  [[ "$output" != *"CAVEMAN"* ]]
}

@test "caveman: session_id con caratteri strani non esce dalla cartella" {
  mkdir -p "$HOME/.claude"; echo caveman >"$HOME/.caveman-sessions-x.mode"
  run cave_render '../../.caveman-sessions-x'
  [[ "$output" != *"CAVEMAN"* ]]
}

@test "caveman: flag di sessione che è un symlink viene ignorato" {
  mkdir -p "$HOME/.claude/.caveman-sessions"
  echo caveman >"$BATS_TEST_TMPDIR/target"
  ln -s "$BATS_TEST_TMPDIR/target" "$HOME/.claude/.caveman-sessions/lnk.mode"
  run cave_render lnk
  [[ "$output" != *"CAVEMAN"* ]]
}
