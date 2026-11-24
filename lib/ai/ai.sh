#!/usr/bin/env bash
# devbar: dispatch generico dell'AI setup (ai-status, ai-install, tool-install).
#
# Interfaccia per-tool (<t> = nome tool con '-' -> '_'; es. rtk, tokensave):
#   ai_<t>_supports <harness>            rc 0 se il tool supporta l'harness
#   ai_<t>_installed                     rc 0 se il binario/tool è presente
#   ai_<t>_state <harness>               stampa installed|outdated|missing
#                                        (chiamata solo se supportato e installato)
#   ai_<t>_install_cmds <harness>...     stampa il piano, una riga per comando
#   ai_<t>_install <harness>...          esegue l'install; rc != 0 = errore
#                                        (stdout del tool va su stderr: lo gestisce il dispatch)
#   ai_<t>_tool_install_cmd              (opzionale) comando che installa il binario
#   ai_<t>_tool_install                  (opzionale) esegue l'install del binario
# Un nuovo tool = un nuovo file in lib/ai/ con queste funzioni.

# _ai_error <messaggio>: stampa {"status":"error","error":...}, rc 2.
_ai_error() {
  jq -nc --arg e "$1" '{status:"error",error:$e}'
  return 2
}

# _ai_fn <tool> <suffisso>: nome funzione se esiste, altrimenti rc 1.
_ai_fn() {
  local fn="ai_${1//-/_}_$2"
  [ "$(type -t "$fn")" = function ] || return 1
  printf '%s' "$fn"
}

# _ai_tool_valid <tool>: solo [a-z-] e interfaccia presente.
_ai_tool_valid() {
  case "$1" in '' | *[!a-z-]* | -*) return 1 ;; esac
  _ai_fn "$1" supports >/dev/null
}

_ai_harness_valid() {
  local id
  for id in $DEVBAR_HARNESS_IDS; do [ "$id" = "$1" ] && return 0; done
  return 1
}

# _ai_config_add_harnesses <id>...: aggiunge a .harnesses (atomico, dedupe,
# ordine e altre chiavi preservati). Config rotta: avviso e nessuna scrittura.
_ai_config_add_harnesses() {
  local file dir cur tmp
  file="$(devbar_config_path)"
  dir="$(dirname "$file")"
  if [ -f "$file" ]; then
    if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
      echo "devbar: config non valida: $file (harnesses non aggiornati)" >&2
      return 0
    fi
    cur="$(cat "$file")"
  else
    cur='{}'
  fi
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.config.XXXXXX")"
  jq '.harnesses = (reduce $ARGS.positional[] as $h
        ((if (.harnesses | type) == "array" then .harnesses else [] end);
         if index($h) then . else . + [$h] end))' \
    --args "$@" <<<"$cur" >"$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file"
}

# action_ai_status <tool>
action_ai_status() {
  local tool="${1:-}" id state inst=false hs="[]" f
  _ai_tool_valid "$tool" || { _ai_error "tool sconosciuto: $tool"; return 2; }
  "$(_ai_fn "$tool" installed)" && inst=true
  for id in $DEVBAR_HARNESS_IDS; do
    if ! "$(_ai_fn "$tool" supports)" "$id"; then
      state=unsupported
    elif [ "$inst" = false ]; then
      state=missing
    else
      f="$(_ai_fn "$tool" state)"
      state="$("$f" "$id" 2>/dev/null)" || state=missing
      [ -n "$state" ] || state=missing
    fi
    hs="$(jq -c --arg i "$id" --arg s "$state" '. + [{id:$i,state:$s}]' <<<"$hs")"
  done
  jq -nc --arg t "$tool" --argjson i "$inst" --argjson h "$hs" \
    '{tool:$t,installed:$i,harnesses:$h}'
}

# action_ai_install <tool> <harness>... [--yes]
action_ai_install() {
  local tool="${1:-}" yes=false h harnesses=() cmds plan rc=0
  [ $# -gt 0 ] && shift
  for h in "$@"; do
    if [ "$h" = "--yes" ]; then yes=true; else harnesses+=("$h"); fi
  done
  _ai_tool_valid "$tool" || { _ai_error "tool sconosciuto: $tool"; return 2; }
  [ ${#harnesses[@]} -gt 0 ] || { _ai_error "uso: devbar run ai-install <tool> <harness>... [--yes]"; return 2; }
  for h in "${harnesses[@]}"; do
    _ai_harness_valid "$h" || { _ai_error "harness non valido: $h"; return 2; }
    "$(_ai_fn "$tool" supports)" "$h" || { _ai_error "harness non supportato da $tool: $h"; return 2; }
  done
  cmds="$("$(_ai_fn "$tool" install_cmds)" "${harnesses[@]}")"
  plan="$(jq -Rn '[inputs | select(length > 0)]' <<<"$cmds")"
  if [ "$yes" = false ]; then
    jq -nc --arg t "$tool" --argjson c "$plan" '{tool:$t,plan:true,commands:$c}'
    return 0
  fi
  "$(_ai_fn "$tool" installed)" || { _ai_error "$tool non installato"; return 2; }
  "$(_ai_fn "$tool" install)" "${harnesses[@]}" >&2 || rc=$?
  [ "$rc" -eq 0 ] || { _ai_error "installazione $tool fallita (rc $rc)"; return 2; }
  _ai_config_add_harnesses "${harnesses[@]}" || { _ai_error "scrittura config fallita"; return 2; }
  action_ai_status "$tool"
}

# action_tool_install <tool> [--yes]: installa il binario del tool.
action_tool_install() {
  local tool="${1:-}" yes=false a cmd rc=0 inst=false
  [ $# -gt 0 ] && shift
  for a in "$@"; do [ "$a" = "--yes" ] && yes=true; done
  if ! _ai_tool_valid "$tool" || ! _ai_fn "$tool" tool_install >/dev/null; then
    _ai_error "tool-install non disponibile per: $tool"
    return 2
  fi
  cmd="$("$(_ai_fn "$tool" tool_install_cmd)")"
  if [ "$yes" = false ]; then
    jq -nc --arg t "$tool" --arg c "$cmd" '{tool:$t,plan:true,commands:[$c]}'
    return 0
  fi
  "$(_ai_fn "$tool" tool_install)" >&2 || rc=$?
  [ "$rc" -eq 0 ] || { _ai_error "installazione $tool fallita (rc $rc)"; return 2; }
  "$(_ai_fn "$tool" installed)" && inst=true
  jq -nc --arg t "$tool" --argjson i "$inst" '{tool:$t,installed:$i}'
}
