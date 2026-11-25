#!/usr/bin/env bash
# devbar: init progetto (project-status, project-apply).
#
# Origine caveman: i file e le regole di _proj_caveman_targets replicano
# src/tools/caveman-init.js del plugin caveman (github.com/JuliusBrussee/caveman,
# v4.2.0, licenza Apache-2.0). Il testo della regola è in lib/project/caveman-rule.md
# (copia di RULE_BODY / src/rules/caveman-activate.md). Resta fuori OpenClaw
# (installazione globale, non per-repo). Nessuna modifica di CLAUDE.md.

_PROJ_FENCE_BEGIN='<!-- caveman-begin -->'
_PROJ_FENCE_END='<!-- caveman-end -->'
_PROJ_SENTINEL='Respond terse like smart caveman'

# _proj_caveman_targets: "<file>|<modo>|<frontmatter>" (modo replace|append).
_proj_caveman_targets() {
  printf '%s\n' \
    '.cursor/rules/caveman.mdc|replace|cursor' \
    '.windsurf/rules/caveman.md|replace|windsurf' \
    '.clinerules/caveman.md|replace|none' \
    '.github/copilot-instructions.md|append|none' \
    '.opencode/AGENTS.md|append|none' \
    'AGENTS.md|append|none'
}

_proj_frontmatter() {
  case "$1" in
    cursor) printf -- '---\ndescription: "Caveman mode — terse communication that preserves technical substance and exact code/errors"\nalwaysApply: true\n---\n\n' ;;
    windsurf) printf -- '---\ntrigger: always_on\n---\n\n' ;;
  esac
}

_proj_rule_file() { printf '%s' "$DEVBAR_ROOT/lib/project/caveman-rule.md"; }

# _proj_fenced_block: blocco con marcatori (corpo senza righe vuote finali).
_proj_fenced_block() {
  printf '%s\n' "$_PROJ_FENCE_BEGIN"
  awk '{ l[NR]=$0 } END { n=NR; while (n>0 && l[n]=="") n--; for (i=1;i<=n;i++) print l[i] }' "$(_proj_rule_file)"
  printf '%s\n' "$_PROJ_FENCE_END"
}

# _proj_fence_pair <file>: rc 0 se esattamente una coppia BEGIN..END ordinata.
_proj_fence_pair() {
  local f="$1" b e
  b="$(grep -cxF "$_PROJ_FENCE_BEGIN" "$f" || true)"
  e="$(grep -cxF "$_PROJ_FENCE_END" "$f" || true)"
  [ "$b" = 1 ] && [ "$e" = 1 ] || return 1
  [ "$(grep -nxF "$_PROJ_FENCE_BEGIN" "$f" | cut -d: -f1)" -lt "$(grep -nxF "$_PROJ_FENCE_END" "$f" | cut -d: -f1)" ]
}

# _proj_caveman_file_state <file-assoluto> <modo>:
#   ok | add | append | refresh | symlink | blocked (non toccato: danneggiato/legacy/esistente)
_proj_caveman_file_state() {
  local f="$1" mode="$2"
  if [ -L "$f" ]; then echo symlink; return; fi
  if [ ! -e "$f" ]; then echo add; return; fi
  if [ "$mode" = replace ]; then
    if grep -qF "$_PROJ_SENTINEL" "$f"; then echo ok; else echo blocked; fi
    return
  fi
  if grep -qF "$_PROJ_FENCE_BEGIN" "$f" || grep -qF "$_PROJ_FENCE_END" "$f"; then
    if ! _proj_fence_pair "$f"; then echo blocked; return; fi
    if [ "$(awk -v b="$_PROJ_FENCE_BEGIN" -v e="$_PROJ_FENCE_END" \
      '$0==b {p=1} p {print} $0==e {p=0}' "$f")" = "$(_proj_fenced_block)" ]; then
      echo ok
    else echo refresh; fi
    return
  fi
  if grep -qF "$_PROJ_SENTINEL" "$f"; then echo blocked; else echo append; fi
}

# _proj_caveman_write <file-assoluto> <modo> <frontmatter> <stato>
_proj_caveman_write() {
  local f="$1" mode="$2" fm="$3" st="$4" sep
  case "$st" in
    add)
      if [ "$mode" = replace ]; then
        { _proj_frontmatter "$fm"; cat "$(_proj_rule_file)"; } | devbar_write_file "$f"
      else
        _proj_fenced_block | devbar_write_file "$f"
      fi
      ;;
    append)
      case "$(tail -c 2 "$f" | od -An -tx1 | tr -d ' \n')" in
        0a0a) sep='' ;;
        *0a) sep=$'\n' ;;
        *) sep=$'\n\n' ;;
      esac
      { cat "$f"; printf '%s' "$sep"; _proj_fenced_block; } | devbar_write_file "$f"
      ;;
    refresh)
      BLK="$(_proj_fenced_block)" awk -v b="$_PROJ_FENCE_BEGIN" -v e="$_PROJ_FENCE_END" '
        $0==b { print ENVIRON["BLK"]; skip=1; next }
        skip && $0==e { skip=0; next }
        !skip' "$f" | devbar_write_file "$f"
      ;;
  esac
}

# _proj_check_rtk: JSON del check rtk (hook globale, nessun file nel repo).
_proj_check_rtk() {
  local st n
  st="$(action_ai_status rtk 2>/dev/null)" || st='{"installed":false,"harnesses":[]}'
  n="$(jq -r '[.harnesses[] | select(.state == "installed")] | length' <<<"$st" 2>/dev/null || echo 0)"
  if [ "${n:-0}" -gt 0 ]; then
    jq -nc '{tool:"rtk",ok:true,detail:"hook globale installato",willWrite:[]}'
  else
    jq -nc '{tool:"rtk",ok:false,detail:"hook globale RTK non installato (usa Impostazioni, AI setup)",willWrite:[]}'
  fi
}

# _proj_check_caveman <root>
_proj_check_caveman() {
  local root="$1" rel mode fm st writes=() blocked=() detail
  while IFS='|' read -r rel mode fm; do
    st="$(_proj_caveman_file_state "$root/$rel" "$mode")"
    case "$st" in
      add | append | refresh) writes+=("$rel") ;;
      blocked) blocked+=("$rel") ;;
    esac
  done < <(_proj_caveman_targets)
  if [ ${#writes[@]} -eq 0 ]; then
    detail="regola caveman presente"
  else
    detail="regola caveman da scrivere in ${#writes[@]} file"
  fi
  [ ${#blocked[@]} -eq 0 ] || detail="$detail; non toccati (esistenti o marcatori danneggiati): ${blocked[*]}"
  jq -nc --arg d "$detail" --argjson ok "$([ ${#writes[@]} -eq 0 ] && echo true || echo false)" \
    '{tool:"caveman",ok:$ok,detail:$d,willWrite:$ARGS.positional}' --args ${writes[@]+"${writes[@]}"}
}

# _proj_gitpath <root> <nome>: percorso assoluto di git --git-path <nome>.
_proj_gitpath() {
  local p
  p="$(git -C "$1" rev-parse --git-path "$2")" || return 1
  case "$p" in /*) printf '%s' "$p" ;; *) printf '%s/%s' "$1" "$p" ;; esac
}

_PROJ_TS_HOOKS="post-checkout post-commit post-merge"

# _proj_ts_state <root>: stampa ok | noindex | nohook.
# `tokensave status` non espone un segnale affidabile di indice da aggiornare
# (solo ultimo sync): ok = .tokensave/ esiste e tutti e tre gli hook
# (post-checkout, post-commit, post-merge) richiamano tokensave.
_proj_ts_state() {
  local root="$1" h f
  [ -d "$root/.tokensave" ] || { echo noindex; return; }
  for h in $_PROJ_TS_HOOKS; do
    f="$(_proj_gitpath "$root" "hooks/$h")"
    if ! { [ -f "$f" ] && grep -q tokensave "$f" 2>/dev/null; }; then echo nohook; return; fi
  done
  echo ok
}

_PROJ_TS_HOOK_NOTE="gli hook git post-checkout, post-commit e post-merge vengono scritti: hook esistenti non tokensave (husky, core.hooksPath) possono esserne toccati"

_proj_check_tokensave() {
  local root="$1" st h hooks=()
  st="$(_proj_ts_state "$root")"
  if [ "$st" != ok ] && ! command -v tokensave >/dev/null 2>&1; then
    jq -nc '{tool:"tokensave",ok:false,detail:"tokensave non installato (usa AI setup, Init tokensave)",willWrite:[]}'
    return
  fi
  for h in $_PROJ_TS_HOOKS; do hooks+=("$(_proj_gitpath "$root" "hooks/$h")"); done
  case "$st" in
    ok) jq -nc '{tool:"tokensave",ok:true,detail:"indice e git hook presenti",willWrite:[]}' ;;
    noindex)
      jq -nc --arg d "$root/.tokensave/" --arg x "$(_proj_gitpath "$root" info/exclude)" --arg n "$_PROJ_TS_HOOK_NOTE" \
        '{tool:"tokensave",ok:false,detail:("indice assente; " + $n),willWrite:([$d,$x] + $ARGS.positional)}' --args "${hooks[@]}" ;;
    nohook)
      jq -nc --arg n "$_PROJ_TS_HOOK_NOTE" \
        '{tool:"tokensave",ok:false,detail:("git hook assenti o incompleti; " + $n),willWrite:$ARGS.positional}' --args "${hooks[@]}" ;;
  esac
}

# _proj_root <dir>: stampa il toplevel git, o rc 2 (l'errore lo stampa il chiamante).
_proj_root() {
  local d="${1:-}"
  [ -n "$d" ] && [ -d "$d" ] || return 2
  git -C "$d" rev-parse --show-toplevel 2>/dev/null || return 2
}

# _proj_te_enabled <root>: stampa true|false (config effettiva di te per il repo), rc 1 se illeggibile.
_proj_te_enabled() {
  local te v
  te="$(te_bin)" || return 1
  v="$("$te" --cwd "$1" config show 2>/dev/null </dev/null | jq -r '.enabled' 2>/dev/null)" || return 1
  case "$v" in true | false) printf '%s' "$v" ;; *) return 1 ;;
  esac
}

# _proj_te_config_path <root>: config di te per questo repo (<repo di te>/config.json), accanto
# alla cartella di stato dell'harness. rc 1 se non si legge.
_proj_te_config_path() {
  local te state
  te="$(te_bin)" || return 1
  state="$("$te" --cwd "$1" status --json 2>/dev/null </dev/null | jq -r '.state // empty' 2>/dev/null)" || return 1
  [ -n "$state" ] || return 1
  printf '%s/config.json' "$(dirname "$state")"
}

# _proj_check_tokeneconomizer <root>: acceso sul repo = plugin in almeno un harness e enabled
# vero. Spento: willWrite è la config di te del repo (te config set enabled=on).
_proj_check_tokeneconomizer() {
  local root="$1" st n en path
  if ! te_clone_dir >/dev/null; then
    jq -nc '{tool:"tokeneconomizer",ok:false,detail:"TokenEconomizer non installato (usa Impostazioni, AI setup)",willWrite:[]}'
    return 0
  fi
  st="$(action_ai_status tokeneconomizer 2>/dev/null)" || st='{"harnesses":[]}'
  n="$(jq -r '[.harnesses[] | select(.state == "installed")] | length' <<<"$st" 2>/dev/null || echo 0)"
  if [ "${n:-0}" -eq 0 ]; then
    jq -nc '{tool:"tokeneconomizer",ok:false,detail:"plugin TokenEconomizer in nessun harness (usa Impostazioni, AI setup)",willWrite:[]}'
    return 0
  fi
  en="$(_proj_te_enabled "$root")" || {
    jq -nc '{tool:"tokeneconomizer",ok:false,detail:"stato di TokenEconomizer non leggibile",willWrite:[]}'
    return 0
  }
  if [ "$en" = true ]; then
    jq -nc '{tool:"tokeneconomizer",ok:true,detail:"attivo su questo repo",willWrite:[]}'
    return 0
  fi
  path="$(_proj_te_config_path "$root")" || path=""
  jq -nc --arg p "$path" '{tool:"tokeneconomizer",ok:false,detail:"spento su questo repo",willWrite:(if $p == "" then [] else [$p] end)}'
}

_proj_status_json() {
  local root="$1"
  jq -nc --arg p "$root" --argjson r "$(_proj_check_rtk)" \
    --argjson c "$(_proj_check_caveman "$root")" --argjson t "$(_proj_check_tokensave "$root")" \
    --argjson e "$(_proj_check_tokeneconomizer "$root")" \
    '{path:$p,checks:[$r,$c,$t,$e]}'
}

action_project_status() {
  local root
  root="$(_proj_root "${1:-}")" || { _ai_error "non è un repo git: ${1:-}"; return 2; }
  _proj_status_json "$root"
}

action_project_apply() {
  local dir="" yes=false a root rel mode fm st ts rc=0
  for a in "$@"; do
    if [ "$a" = "--yes" ]; then yes=true; elif [ -z "$dir" ]; then dir="$a"; fi
  done
  root="$(_proj_root "$dir")" || { _ai_error "non è un repo git: $dir"; return 2; }
  if [ "$yes" = false ]; then
    _proj_status_json "$root"
    return 0
  fi
  # Ogni strumento necessario si verifica prima di scrivere qualsiasi file.
  ts="$(_proj_ts_state "$root")"
  if [ "$ts" != ok ] && ! command -v tokensave >/dev/null 2>&1; then
    jq -nc '{status:"error",error:"tokensave non installato: nessun file scritto (usa AI setup, Init tokensave)"}'
    return 3
  fi
  while IFS='|' read -r rel mode fm; do
    st="$(_proj_caveman_file_state "$root/$rel" "$mode")"
    case "$st" in
      add | append | refresh)
        _proj_caveman_write "$root/$rel" "$mode" "$fm" "$st" || { _ai_error "scrittura fallita: $rel"; return 2; }
        ;;
    esac
  done < <(_proj_caveman_targets)
  # tokensave: init (indice + hook del repo) oppure solo hook se l'indice c'è.
  # `tokensave install --git-hook yes` non va bene: configura anche gli agenti.
  # tokensave scrive da sé: si registra prima lo stato dei percorsi che tocca (willWrite).
  case "$ts" in
    noindex | nohook)
      local h snap=()
      [ "$ts" = nohook ] || snap+=("$root/.tokensave" "$(_proj_gitpath "$root" info/exclude)")
      for h in $_PROJ_TS_HOOKS; do snap+=("$(_proj_gitpath "$root" "hooks/$h")"); done
      journal_before "${snap[@]}" </dev/null || { _ai_error "backup prima di tokensave fallito"; return 2; }
      ;;
  esac
  case "$ts" in
    noindex) (cd "$root" && tokensave init --git-hook </dev/null) >&2 || rc=$? ;;
    nohook) (cd "$root" && tokensave githooks on --local </dev/null) >&2 || rc=$? ;;
  esac
  [ "$rc" -eq 0 ] || { _ai_error "tokensave fallito (rc $rc)"; return 2; }
  # TokenEconomizer: solo ciò che il piano mostra (willWrite del check: plugin in un harness e
  # spento su questo repo). Config di te fuori dal repo, registrata.
  local te tecfg
  tecfg="$(_proj_check_tokeneconomizer "$root" | jq -r '.willWrite[0] // empty')"
  if [ -n "$tecfg" ] && te="$(te_bin)"; then
    journal_before "$tecfg" </dev/null || { _ai_error "backup prima di TokenEconomizer fallito"; return 2; }
    "$te" --cwd "$root" config set enabled=on </dev/null >&2 || { _ai_error "TokenEconomizer fallito"; return 2; }
  fi
  _proj_status_json "$root"
}
