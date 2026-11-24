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

# emit <status> <count> <summary> [items-json]: stampa il JSON ed esce.
# action=0 ok=1 error=2 unconfigured=3 (status sconosciuto -> error).
emit() {
  local status="$1" count="$2" summary="$3" items="${4:-[]}" rc
  case "$status" in
    action) rc=0 ;;
    ok) rc=1 ;;
    error) rc=2 ;;
    unconfigured) rc=3 ;;
    *) status=error rc=2 ;;
  esac
  jq -n --arg s "$status" --argjson c "$count" --arg m "$summary" \
    --argjson i "$items" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{status:$s,count:$c,summary:$m,items:$i,checkedAt:$t}'
  exit "$rc"
}

# require_tool <bin>: se manca emette unconfigured (rc 3).
require_tool() {
  command -v "$1" >/dev/null 2>&1 || emit unconfigured 0 "$1 non installato"
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

# extract_json: da stdin stampa dalla prima riga che inizia con '{' in poi
# (i tool possono stampare testo, es. '==> ...', prima del JSON).
extract_json() { awk '/^\{/ {p=1} p'; }
