#!/usr/bin/env bash
# devbar: rilevamento harness e strumenti; check harnesses; check all.

DEVBAR_HARNESS_IDS="claude opencode copilot codex cursor gemini"
# Tool controllati da `detect` (cork = app, vedi detect_tool).
DEVBAR_DETECT_TOOLS="brew colima npm composer rtk tokensave claude-usage cork"

# harness_bin <id>: nome del binario; harness_dir <id>: cartella in $HOME.
harness_bin() {
  case "$1" in
    cursor) echo cursor-agent ;;
    *) echo "$1" ;;
  esac
}
harness_dir() {
  case "$1" in
    claude) echo "$HOME/.claude" ;;
    opencode) echo "$HOME/.config/opencode" ;;
    copilot) echo "$HOME/.copilot" ;;
    codex) echo "$HOME/.codex" ;;
    cursor) echo "$HOME/.cursor" ;;
    gemini) echo "$HOME/.gemini" ;;
  esac
}

# harness_installed <id>: rc 0 se binario in PATH o cartella in $HOME.
harness_installed() {
  command -v "$(harness_bin "$1")" >/dev/null 2>&1 || [ -e "$(harness_dir "$1")" ]
}

# detect_tool <nome>: rc 0 se presente. cork = Cork.app in DEVBAR_APPLICATIONS_DIR.
detect_tool() {
  if [ "$1" = cork ]; then
    [ -d "${DEVBAR_APPLICATIONS_DIR:-/Applications}/Cork.app" ]
  else
    command -v "$1" >/dev/null 2>&1
  fi
}

# cmd_detect: {"harnesses":[{id,installed,managed}],"tools":{...}}
cmd_detect() {
  local managed id t hs="[]" tools="{}" inst man
  managed="$(config_get '.harnesses')"
  for id in $DEVBAR_HARNESS_IDS; do
    inst=false
    harness_installed "$id" && inst=true
    man="$(jq -r --arg i "$id" 'index($i) != null' <<<"$managed")"
    hs="$(jq -c --arg i "$id" --argjson a "$inst" --argjson m "$man" \
      '. + [{id:$i,installed:$a,managed:$m}]' <<<"$hs")"
  done
  for t in $DEVBAR_DETECT_TOOLS; do
    inst=false
    detect_tool "$t" && inst=true
    tools="$(jq -c --arg t "$t" --argjson v "$inst" '. + {($t):$v}' <<<"$tools")"
  done
  jq -nc --argjson h "$hs" --argjson t "$tools" --argjson a "$(detect_ai_tools)" \
    '{harnesses:$h,tools:$t,aiTools:$a}'
}

# Strumenti dell'AI setup mostrati nel pannello (ordine dei pulsanti).
DEVBAR_AI_TOOLS="rtk caveman tokensave statusline"

# detect_ai_tools: {"<tool>":bool}: true se almeno un harness installato è supportato.
detect_ai_tools() {
  local t id ok out="{}"
  for t in $DEVBAR_AI_TOOLS; do
    ok=false
    for id in $DEVBAR_HARNESS_IDS; do
      if harness_installed "$id" && "ai_${t}_supports" "$id"; then ok=true; break; fi
    done
    out="$(jq -c --arg t "$t" --argjson v "$ok" '. + {($t):$v}' <<<"$out")"
  done
  printf '%s' "$out"
}

# check_harnesses: rc 0 se ci sono harness installati non gestiti (items = id).
check_harnesses() {
  local managed id items="[]" n
  managed="$(config_get '.harnesses')"
  for id in $DEVBAR_HARNESS_IDS; do
    harness_installed "$id" || continue
    if [ "$(jq -r --arg i "$id" 'index($i) != null' <<<"$managed")" = false ]; then
      items="$(jq -c --arg i "$id" '. + [$i]' <<<"$items")"
    fi
  done
  n="$(jq 'length' <<<"$items")"
  if [ "$n" -gt 0 ]; then
    emit action "$n" "$n harness non gestiti" "$items"
  fi
  emit ok 0 "nessun nuovo harness" "[]"
}

DEVBAR_ALL_CHECKS="brew-outdated brew-vulns npm-audit composer-audit colima rtk tokensave tokeneconomizer caveman claude-usage harnesses"

# Timeout di ogni check dentro check all (secondi). npm/composer audit scorrono
# tutti i repo, uno dopo l'altro, e brew-outdated può lanciare `brew update`: più tempo. DEVBAR_CHECK_TIMEOUT (intero > 0)
# vale per tutti i check. L'app somma questi valori per il suo timeout di riserva
# (StatusStore.checkTimeouts, verificato da un test contro `devbar check-timeouts`).
DEVBAR_CHECK_TIMEOUT_DEFAULT=60
DEVBAR_CHECK_TIMEOUT_AUDIT=300

# check_timeout_secs <nome>: timeout del check.
check_timeout_secs() {
  local t="${DEVBAR_CHECK_TIMEOUT:-}"
  if [[ "$t" =~ ^[0-9]+$ ]] && [ "$t" -gt 0 ]; then echo "$t"; return; fi
  case "${1:-}" in
    npm-audit | composer-audit | brew-outdated) echo "$DEVBAR_CHECK_TIMEOUT_AUDIT" ;;
    *) echo "$DEVBAR_CHECK_TIMEOUT_DEFAULT" ;;
  esac
}

# cmd_check_timeouts: {"<check>":<secondi>,...} per i check di check all.
cmd_check_timeouts() {
  local name out="{}"
  for name in $DEVBAR_ALL_CHECKS; do
    out="$(jq -c --arg k "$name" --argjson v "$(check_timeout_secs "$name")" '. + {($k):$v}' <<<"$out")"
  done
  printf '%s\n' "$out"
}

# tree_pids <pid>: il pid e tutti i discendenti (figli prima del padre).
tree_pids() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do tree_pids "$c"; done
  echo "$1"
}

# run_timed <secs> <outfile> <cmd...>: stdout su <outfile>, rc del comando;
# allo scadere (macOS non ha `timeout`) TERM all'albero, KILL dopo 1 s, rc 124.
run_timed() {
  local secs="$1" outf="$2" pid pids i=0 rc=0
  shift 2
  "$@" >"$outf" 2>/dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge $((secs * 10)) ]; then
      # elenco preso prima di uccidere: i nipoti orfani non sarebbero più figli
      pids="$(tree_pids "$pid")"
      # shellcheck disable=SC2086
      kill -TERM $pids 2>/dev/null || true
      sleep 1
      # shellcheck disable=SC2086
      kill -KILL $pids 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.1
    i=$((i + 1))
  done
  wait "$pid" || rc=$?
  return "$rc"
}

# check_all_run [--force]: esegue ogni check in un processo a parte, con timeout.
check_all_run() {
  local name out rc res all="{}" fargs=() tmp
  [ "${1:-}" = "--force" ] && fargs=(--force)
  tmp="$(mktemp "${TMPDIR:-/tmp}/devbar-check.XXXXXX")"
  for name in $DEVBAR_ALL_CHECKS; do
    rc=0
    run_timed "$(check_timeout_secs "$name")" "$tmp" "$DEVBAR_ROOT/bin/devbar" check "$name" ${fargs[@]+"${fargs[@]}"} || rc=$?
    if [ "$rc" -eq 124 ]; then
      all="$(jq -c --arg k "$name" '. + {($k):{rc:2,status:"error",summary:"timeout"}}' <<<"$all")"
      continue
    fi
    out="$(cat "$tmp")"
    res="$(jq -ce --argjson rc "$rc" 'select(type == "object") | . + {rc:$rc}' <<<"$out" 2>/dev/null)" || res=""
    if [ -z "$res" ]; then
      res="$(jq -nc --argjson rc "$rc" '{rc:$rc,status:"error",summary:"output non valido"}')"
    fi
    all="$(jq -c --arg k "$name" --argjson v "$res" '. + {($k):$v}' <<<"$all")"
  done
  rm -f "$tmp"
  printf '%s\n' "$all"
  return 1
}

# check_all [--force]: aggregato sotto lock; rc 1 (l'app legge l'rc per check).
check_all() {
  with_lock check_all_run "$@"
}
