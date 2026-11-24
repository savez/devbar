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
  jq -nc --argjson h "$hs" --argjson t "$tools" '{harnesses:$h,tools:$t}'
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

DEVBAR_ALL_CHECKS="brew-outdated brew-vulns npm-audit composer-audit colima rtk tokensave caveman claude-usage harnesses"

# check_all_run [--force]: esegue ogni check in un processo a parte.
check_all_run() {
  local name out rc res all="{}" fargs=()
  [ "${1:-}" = "--force" ] && fargs=(--force)
  for name in $DEVBAR_ALL_CHECKS; do
    rc=0
    out="$("$DEVBAR_ROOT/bin/devbar" check "$name" ${fargs[@]+"${fargs[@]}"} 2>/dev/null)" || rc=$?
    res="$(jq -ce --argjson rc "$rc" 'select(type == "object") | . + {rc:$rc}' <<<"$out" 2>/dev/null)" || res=""
    if [ -z "$res" ]; then
      res="$(jq -nc --argjson rc "$rc" '{rc:$rc,status:"error",summary:"output non valido"}')"
    fi
    all="$(jq -c --arg k "$name" --argjson v "$res" '. + {($k):$v}' <<<"$all")"
  done
  printf '%s\n' "$all"
  return 1
}

# check_all [--force]: aggregato sotto lock; rc 1 (l'app legge l'rc per check).
check_all() {
  with_lock check_all_run "$@"
}
