#!/usr/bin/env bash
# devbar: funzioni comuni (config, cache, lock, emit).
# Compatibile con bash 3.2 (macOS di sistema).

DEVBAR_DEFAULT_CONFIG='{"repoRoots":[],"scanDepth":4,"dailyCheckTime":"09:00","harnesses":[],"brewExclude":[],"terminal":"Terminal","launchAtLogin":true}'

devbar_config_path() { printf '%s' "${DEVBAR_CONFIG:-$HOME/.config/devbar/config.json}"; }
devbar_cache_dir() { printf '%s' "${DEVBAR_CACHE_DIR:-$HOME/.cache/devbar}"; }

# config_get <jq-path>: valore dal config, con default se assente o rotto.
config_get() {
  local path="$1" file merged
  file="$(devbar_config_path)"
  merged="$DEVBAR_DEFAULT_CONFIG"
  if [ -f "$file" ]; then
    if jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
      merged="$(jq -c --argjson d "$DEVBAR_DEFAULT_CONFIG" '$d + .' "$file")"
    else
      echo "devbar: config non valida: $file (uso i default)" >&2
    fi
  fi
  jq -r "$path | if type == \"string\" then . else tojson end" <<<"$merged"
}

# cache_fresh <name> <minutes>: rc 0 se la cache è più giovane di <minutes>.
cache_fresh() {
  local f
  f="$(devbar_cache_dir)/$1.json"
  [ -f "$f" ] || return 1
  [ -z "$(find "$f" -mmin "+$2" 2>/dev/null)" ]
}

# cache_read <name>: stampa il contenuto della cache.
cache_read() { cat "$(devbar_cache_dir)/$1.json"; }

# cache_write <name>: scrive stdin nella cache (atomico).
cache_write() {
  local dir tmp
  dir="$(devbar_cache_dir)"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.$1.XXXXXX")"
  cat >"$tmp"
  mv "$tmp" "$dir/$1.json"
}

# emit <status> <count> <summary> [items-json] [extra-json]: stampa il JSON ed esce.
# extra-json: oggetto unito al top level (campi aggiuntivi specifici del check).
# action=0 ok=1 error=2 unconfigured=3 (status sconosciuto -> error).
emit() {
  local status="$1" count="$2" summary="$3" items="${4:-[]}" extra="${5:-}" rc
  case "$status" in
    action) rc=0 ;;
    ok) rc=1 ;;
    error) rc=2 ;;
    unconfigured) rc=3 ;;
    *) status=error rc=2 ;;
  esac
  [ -n "$extra" ] || extra='{}'
  jq -n --arg s "$status" --argjson c "$count" --arg m "$summary" \
    --argjson i "$items" --argjson x "$extra" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{status:$s,count:$c,summary:$m,items:$i,checkedAt:$t} + $x'
  exit "$rc"
}

# require_tool <bin>: se manca emette unconfigured (rc 3).
require_tool() {
  command -v "$1" >/dev/null 2>&1 || emit unconfigured 0 "$1 non installato"
}

# tool_version <cmd...>: primo numero di versione stampato dal comando, "sconosciuta" se manca.
tool_version() {
  local v
  v="$("$@" 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)" || true
  printf '%s' "${v:-sconosciuta}"
}

# format_error <strumento> <comando di versione...>: l'output dello strumento non ha la forma
# attesa (formato cambiato). rc 2 con la versione nel messaggio, mai un risultato 0.
format_error() {
  local tool="$1"
  shift
  emit error 0 "formato di $tool non riconosciuto (versione $(tool_version "$@"))"
}

# with_lock <cmd...>: un solo processo alla volta; altrimenti busy (rc 2).
with_lock() {
  local dir lock pid rc=0
  dir="$(devbar_cache_dir)"
  lock="$dir/devbar.lock.d"
  mkdir -p "$dir"
  if ! mkdir "$lock" 2>/dev/null; then
    pid="$(cat "$lock/pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      # lock orfano (processo morto): ripresa
      rm -rf "$lock"
    fi
    if ! mkdir "$lock" 2>/dev/null; then
      jq -n '{status:"error",error:"busy"}'
      exit 2
    fi
  fi
  echo "$$" >"$lock/pid"
  # rilascio garantito anche se il comando chiama emit/exit o arriva un segnale
  DEVBAR_LOCK_DIR="$lock"
  trap 'rm -rf "$DEVBAR_LOCK_DIR"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@" || rc=$?
  rm -rf "$lock"
  trap - EXIT INT TERM
  return "$rc"
}

# devbar_hash <testo>: hash breve (16 hex) per i nomi di cache.
devbar_hash() { printf '%s' "$1" | shasum -a 256 | cut -c1-16; }

# extract_json: da stdin stampa dalla prima riga che inizia con '{' in poi
# (i tool possono stampare testo, es. '==> ...', prima del JSON).
extract_json() { awk '/^\{/ {p=1} p'; }

# devbar_write_file <target>: scrive stdin su <target> (Ruling E).
# File temporaneo nella cartella del target + mv; mantiene il modo del target
# se esisteva; se il target è un symlink scrive sul file risolto (il link resta);
# nessun temporaneo residuo in caso di errore.
devbar_write_file() {
  local target="$1" next dir tmp mode n=0
  while [ -L "$target" ]; do
    next="$(readlink "$target")"
    case "$next" in /*) target="$next" ;; *) target="$(dirname "$target")/$next" ;; esac
    n=$((n + 1))
    [ "$n" -le 20 ] || { echo "devbar: troppi symlink: $1" >&2; return 1; }
  done
  dir="$(dirname "$target")"
  # registro delle modifiche (lib/journal.sh): stato di prima, backup; se fallisce non si scrive
  if declare -F journal_before >/dev/null; then journal_before "$target" </dev/null || return 1; fi
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.devbar-write.XXXXXX")" || return 1
  if [ -e "$target" ]; then
    mode="$(stat -f '%Lp' "$target" 2>/dev/null || stat -c '%a' "$target" 2>/dev/null || true)"
  fi
  if ! cat >"$tmp"; then rm -f "$tmp"; return 1; fi
  if [ -n "${mode:-}" ] && ! chmod "$mode" "$tmp"; then rm -f "$tmp"; return 1; fi
  mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }
}

# config_update <jq-filter> [jq-args...]: applica il filtro al config e lo riscrive
# con devbar_write_file (altre chiavi preservate). Config assente: si parte da {}.
# Config rotta (non un oggetto JSON): avviso, nessuna scrittura, rc 2.
config_update() {
  local filter="$1" file base out
  shift
  file="$(devbar_config_path)"
  if [ -e "$file" ]; then
    if ! base="$(jq -c 'if type == "object" then . else error("non oggetto") end' "$file" 2>/dev/null)"; then
      echo "devbar: config non valida: $file (non modificata)" >&2
      return 2
    fi
  else
    base='{}'
  fi
  out="$(jq "$filter" "$@" <<<"$base")" || return 1
  printf '%s\n' "$out" | devbar_write_file "$file"
}

# inject_block <file> <begin> <end> <contenuto>: sostituisce (o aggiunge in coda) il blocco
# delimitato dai marcatori; il resto del file resta. Scrittura via devbar_write_file.
inject_block() {
  local file="$1" b="$2" e="$3" content="$4" base=""
  if [ -f "$file" ]; then
    base="$(awk -v b="$b" -v e="$e" '$0 ~ b { skip=1; next } $0 ~ e { skip=0; next } !skip' "$file")" || return 1
  fi
  {
    [ -z "$base" ] || printf '%s\n' "$base"
    printf '\n%s\n%s\n%s\n' "$b" "$content" "$e"
  } | devbar_write_file "$file"
}
