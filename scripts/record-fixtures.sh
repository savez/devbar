#!/usr/bin/env bash
# Registra l'output reale degli strumenti che devbar legge, in tests/fixtures/real/.
# Uso: scripts/record-fixtures.sh [cartella-uscita]   (o just record-fixtures)
#
# SOLO LETTURA: ogni comando passa da ro(), che rifiuta tutto ciò che non è nella lista
# qui sotto. Gli audit npm/composer girano solo sul repo di esempio tests/fixtures/sample-repo.
# Ogni uscita viene anonimizzata (home, utente, host, nomi extra in RECORD_EXTRA_REDACT,
# separati da ':') e poi controllata: se contiene ancora un dato personale lo script
# rifiuta di scrivere il file e termina con errore.
# File: <strumento>-<comando>-<versione>.json (.txt se l'uscita non è JSON, es. ha un preambolo).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/tests/fixtures/real}"
SAMPLE="${RECORD_SAMPLE_REPO:-$ROOT/tests/fixtures/sample-repo}"
mkdir -p "$OUT"

# Lista dei comandi consentiti (stringa esatta degli argomenti). Aggiungere qui SOLO letture.
ro_allowed() {
  case "$*" in
    "brew --version" | "brew outdated --json=v2" | "brew vulns --json" | \
      "rtk --version" | "rtk gain -d -f json" | \
      "tokensave --version" | "tokensave gain --all --json --range 7d" | "tokensave discover --json --since 7d" | \
      "colima version" | "colima list --json" | \
      "docker --version" | "docker stats --no-stream --format json" | \
      "claude-usage --version" | "claude-usage --status" | \
      "npm -v" | "npm audit --json" | \
      "composer --version" | "composer audit --format=json --locked") return 0 ;;
  esac
  return 1
}

# ro <cmd...>: esegue un comando consentito (stdout; stderr scartato; rc ignorato).
ro() {
  if ! ro_allowed "$@"; then
    echo "record-fixtures: comando non consentito (solo lettura): $*" >&2
    exit 2
  fi
  "$@" 2>/dev/null
}

have() { command -v "$1" >/dev/null 2>&1; }

version_of() { # version_of <cmd...>: primo x.y[.z] dell'uscita, o "sconosciuta"
  local v
  v="$(ro "$@" | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)" || true
  printf '%s' "${v:-sconosciuta}"
}

sed_esc() { printf '%s' "$1" | sed -e 's/[][\.*^$/|&]/\\&/g'; }

# Dati personali da togliere: home, utente, nome host, extra.
PERSONAL=()
add_personal() { [ "${#1}" -ge 3 ] && PERSONAL+=("$1"); return 0; }
add_personal "${HOME:-}"
add_personal "$(id -un 2>/dev/null)"
add_personal "${USER:-}"
add_personal "$(hostname -s 2>/dev/null)"
add_personal "$(hostname 2>/dev/null)"
add_personal "$(scutil --get ComputerName 2>/dev/null)"
add_personal "$(scutil --get LocalHostName 2>/dev/null)"
EXTRA=()
if [ -n "${RECORD_EXTRA_REDACT:-}" ]; then
  IFS=: read -r -a EXTRA <<<"$RECORD_EXTRA_REDACT"
fi

anonymize() {
  local args=() p
  [ -z "${HOME:-}" ] || args+=(-e "s|$(sed_esc "$HOME")|/Users/anon|g")
  for p in "${PERSONAL[@]}"; do
    [ "$p" = "${HOME:-}" ] || args+=(-e "s|$(sed_esc "$p")|anon|g")
  done
  for p in ${EXTRA[@]+"${EXTRA[@]}"}; do
    [ -z "$p" ] || args+=(-e "s|$(sed_esc "$p")|private-repo|g")
  done
  sed ${args[@]+"${args[@]}"}
}

# leaks <file>: stampa il perché se il file contiene ancora dati personali.
leaks() {
  local f="$1" p
  for p in "${PERSONAL[@]}"; do
    if grep -qiF -- "$p" "$f"; then echo "contiene ancora un dato personale ($p)"; return 0; fi
  done
  if grep -E '/Users/' "$f" | grep -qv '/Users/anon'; then echo "contiene un percorso /Users/ non anonimo"; return 0; fi
  if grep -qE 'ghp_[A-Za-z0-9]{20,}|github_pat_|sk-[A-Za-z0-9]{20,}|xox[bp]-|AKIA[0-9A-Z]{16}|Bearer [A-Za-z0-9._-]{20,}' "$f"; then
    echo "sembra contenere un token"; return 0
  fi
  return 1
}

FAIL=0
# record <nome> <comando di versione...> -- <comando...>
record() {
  local name="$1" raw tmp ext ver why
  shift
  local vcmd=()
  while [ "$1" != "--" ]; do vcmd+=("$1"); shift; done
  shift
  if ! have "$1"; then echo "salto $name: $1 non installato"; return 0; fi
  raw="$(ro "$@")"
  if [ -z "$raw" ]; then echo "salto $name: nessun output (strumento non raggiungibile?)"; return 0; fi
  ver="$(version_of "${vcmd[@]}")"
  if printf '%s\n' "$raw" | jq -s . >/dev/null 2>&1; then ext=json; else ext=txt; fi
  tmp="$(mktemp)"
  printf '%s\n' "$raw" | anonymize >"$tmp"
  if why="$(leaks "$tmp")"; then
    echo "RIFIUTO $name: $why: file non scritto" >&2
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$OUT/$name-$ver.$ext"
  echo "registrato $OUT/$name-$ver.$ext"
}

export HOMEBREW_NO_AUTO_UPDATE=1
record brew-outdated brew --version -- brew outdated --json=v2 || FAIL=1
record brew-vulns brew --version -- brew vulns --json || FAIL=1
record rtk-gain rtk --version -- rtk gain -d -f json || FAIL=1
record tokensave-gain tokensave --version -- tokensave gain --all --json --range 7d || FAIL=1
record tokensave-discover tokensave --version -- tokensave discover --json --since 7d || FAIL=1
record colima-list colima version -- colima list --json || FAIL=1
record docker-stats docker --version -- docker stats --no-stream --format json || FAIL=1
record claude-usage-status claude-usage --version -- claude-usage --status || FAIL=1

if [ -d "$SAMPLE" ]; then
  # gli audit girano nella cartella di esempio (sottoshell: nessun effetto sulla cartella corrente)
  if [ -f "$SAMPLE/package-lock.json" ]; then
    (cd "$SAMPLE" && record npm-audit npm -v -- npm audit --json) || FAIL=1
  fi
  if [ -f "$SAMPLE/composer.lock" ]; then
    (cd "$SAMPLE" && record composer-audit composer --version -- composer audit --format=json --locked) || FAIL=1
  fi
fi

[ "$FAIL" -eq 0 ] || { echo "record-fixtures: alcuni file rifiutati (dati personali)" >&2; exit 1; }
