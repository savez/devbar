#!/usr/bin/env bash
# devbar: check di risparmio token (rtk, tokensave, caveman) e usage Claude.
# Tutti informativi: rc 1 se presenti, rc 3 se assenti, rc 2 se l'output è malformato.

# check_rtk: totali e ultimi 7 giorni da `rtk gain -d -f json`.
check_rtk() {
  require_tool rtk
  local raw out
  raw="$(rtk gain -d -f json 2>/dev/null | extract_json || true)"
  out="$(jq -c '
    select(type == "object" and (.summary | type) == "object"
      and all(.summary.total_saved, .summary.total_input, .summary.avg_savings_pct, .summary.total_commands; type == "number")
      and ((.daily // []) | type) == "array") |
    {saved: (.summary.total_saved // 0), input: (.summary.total_input // 0),
     pct: (.summary.avg_savings_pct // 0), commands: (.summary.total_commands // 0),
     daily: ((.daily // []) | map({date, saved: (.saved_tokens // 0)}) | .[-7:])}' \
    <<<"$raw" 2>/dev/null)" || out=""
  [ -n "$out" ] || format_error rtk rtk --version
  emit ok 0 "RTK: $(jq -r '.saved' <<<"$out") token risparmiati" "[]" "$out"
}

# check_tokensave: gain 7 giorni + turni sostituibili da `discover`.
check_tokensave() {
  require_tool tokensave
  local g d gain missed
  g="$(tokensave gain --all --json --range 7d 2>/dev/null | extract_json || true)"
  gain="$(jq -c 'select(type == "object") |
    select((.saved_tokens | type) == "number" and (.calls | type) == "number") |
    {saved: .saved_tokens, calls: .calls, usd: (.usd // 0)}' <<<"$g" 2>/dev/null)" || gain=""
  [ -n "$gain" ] || format_error tokensave tokensave --version
  d="$(tokensave discover --json --since 7d 2>/dev/null | extract_json || true)"
  missed="$(jq -c 'select(type == "object" and (.replaceable_turns | type) == "number") | .replaceable_turns' <<<"$d" 2>/dev/null)" || missed=""
  [ -n "$missed" ] || format_error tokensave tokensave --version
  local extra
  extra="$(jq -c --argjson m "$missed" '. + {missedTurns: $m}' <<<"$gain")"
  emit ok 0 "tokensave: $missed turni sostituibili" "[]" "$extra"
}

# check_tokeneconomizer: informativo. Attivo = il plugin c'è su almeno un harness scelto in
# devbar e `enabled` non è falso nella config globale di te (assente o rotta = acceso).
# Il dettaglio per harness sta in AI setup; qui nessun conteggio.
check_tokeneconomizer() {
  te_clone_dir >/dev/null || emit unconfigured 0 "TokenEconomizer non installato"
  local harnesses h on=false enabled=true cfg="$HOME/.tokeneconomizer/config.json" msg
  harnesses="$(config_get .harnesses | jq -r 'if type == "array" then .[] else empty end' 2>/dev/null || true)"
  for h in $harnesses; do
    ai_tokeneconomizer_supports "$h" || continue
    if [ "$(ai_tokeneconomizer_state "$h")" = installed ]; then on=true; break; fi
  done
  if [ -f "$cfg" ] && [ "$(jq -r '.enabled' "$cfg" 2>/dev/null || true)" = false ]; then enabled=false; fi
  if [ "$on" = false ]; then
    msg="TokenEconomizer non installato negli harness scelti"
  elif [ "$enabled" = false ]; then
    msg="TokenEconomizer spento"; on=false
  else
    msg="TokenEconomizer attivo"
  fi
  emit ok 0 "$msg" "[]" "$(jq -nc --argjson a "$on" '{active:$a}')"
}

# _caveman_canonical_mode <valore>: modalità canonica del plugin (valori legacy mappati).
# Vuoto o sconosciuto: "caveman", come il default del plugin.
_caveman_canonical_mode() {
  case "${1:-}" in
    off | manual | caveman | ultracave | megacave) printf '%s' "$1" ;;
    ultra) printf 'ultracave' ;;
    wenyan*) printf 'megacave' ;;
    *) printf 'caveman' ;;
  esac
}

# check_caveman: plugin attivo, modalità di default (canonica e grezza), versione.
# Nessuna statistica di risparmio.
check_caveman() {
  local cfg ver raw="" dir settings enabled=false mode active=false
  cfg="$HOME/.config/caveman/config.json"
  dir="$HOME/.claude/plugins/cache/caveman/caveman"
  settings="$HOME/.claude/settings.json"
  ver=""
  if [ -d "$dir" ]; then
    ver="$(find "$dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} + 2>/dev/null | sort -V | tail -n 1)"
  fi
  if [ -f "$cfg" ]; then
    raw="$(jq -r 'if type == "object" then (.defaultMode // "" | tostring) else "" end' "$cfg" 2>/dev/null)" || raw=""
  fi
  if [ -z "$raw" ] && [ -z "$ver" ]; then
    emit unconfigured 0 "caveman non installato"
  fi
  if [ -f "$settings" ] && [ "$(jq -r '.enabledPlugins["caveman@caveman"] == true' "$settings" 2>/dev/null)" = true ]; then
    enabled=true
  fi
  mode="$(_caveman_canonical_mode "$raw")"
  if [ "$enabled" = true ] && [ "$mode" != off ]; then active=true; fi
  local last extra
  last="$(_caveman_canonical_mode "$(config_get '.cavemanLastMode // ""' 2>/dev/null)")"
  [ "$last" != off ] || last=caveman
  extra="$(jq -nc --arg m "$mode" --arg r "$raw" --arg v "$ver" --arg l "$last" --argjson e "$enabled" --argjson a "$active" \
    '{pluginEnabled:$e, mode:$m, rawMode:$r, version:$v, lastMode:$l, active:$a}')"
  emit ok 0 "caveman ${ver:+$ver }($mode)" "[]" "$extra"
}

# check_claude_usage [--force]: inoltra c_pct/c_reset/w_pct/w_reset/stale/auth/error in .usage.
check_claude_usage() {
  require_tool claude-usage
  local args=(--status) raw usage
  if [ "${1:-}" = "--force" ]; then args+=(--force-poll); fi
  raw="$(claude-usage "${args[@]}" 2>/dev/null | extract_json || true)"
  usage="$(jq -c 'select(type == "object" and (has("c_pct") or has("w_pct") or has("auth") or has("error"))) |
    {c_pct, c_reset, w_pct, w_reset, stale, auth, error}' <<<"$raw" 2>/dev/null)" || usage=""
  [ -n "$usage" ] || format_error claude-usage claude-usage --version
  emit ok 0 "usage Claude" "[]" "$(jq -nc --argjson u "$usage" '{usage:$u}')"
}
