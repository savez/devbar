#!/usr/bin/env bash
# devbar: installazione di claude-usage (vedi interfaccia in lib/ai/ai.sh).
# Portato da github.com/sparkfabrik/sparkdock (sjust/scripts/claude-usage.sh), GPLv3.
# Più rigido dell'originale: checksum assente o diverso = errore, mai esecuzione;
# niente fallback sul raw git ref (non verificabile).

_CLAUDE_USAGE_RELEASES="https://github.com/sparkfabrik/claude-usage/releases"

# Non è legato a un harness: nessun harness supportato, solo tool-install.
ai_claude_usage_supports() { return 1; }
ai_claude_usage_installed() { command -v claude-usage >/dev/null 2>&1; }
ai_claude_usage_state() { echo installed; }
ai_claude_usage_install_cmds() { :; }
ai_claude_usage_install() { return 0; }

ai_claude_usage_tool_install_cmd() {
  echo "scarica install.sh e checksums.txt dall'ultima release di sparkfabrik/claude-usage, verifica sha256, esegue install.sh"
}

# _claude_usage_latest_tag: tag dal redirect di /releases/latest (niente API).
_claude_usage_latest_tag() {
  local loc tag
  loc="$(curl -sI --connect-timeout 10 --max-time 30 "$_CLAUDE_USAGE_RELEASES/latest" 2>/dev/null |
    tr -d '\r' | awk 'tolower($1) == "location:" {print $2}' | tail -n 1)"
  tag="${loc##*/tag/}"
  case "$tag" in
    v[0-9]*.[0-9]*.[0-9]*)
      case "$tag" in *[!v0-9.]*) return 1 ;; esac
      printf '%s' "$tag"
      ;;
    *) return 1 ;;
  esac
}

ai_claude_usage_tool_install() {
  local tag base tmp want got rc=0
  command -v curl >/dev/null 2>&1 || { echo "devbar: curl non trovato" >&2; return 1; }
  tag="$(_claude_usage_latest_tag)" || { echo "devbar: tag dell'ultima release non risolto" >&2; return 1; }
  base="$_CLAUDE_USAGE_RELEASES/download/$tag"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/devbar-claude-usage.XXXXXX")" || return 1
  (
    set -e
    curl -fsSL --connect-timeout 10 --max-time 120 -o "$tmp/install.sh" "$base/install.sh"
    curl -fsSL --connect-timeout 10 --max-time 120 -o "$tmp/checksums.txt" "$base/checksums.txt"
    want="$(awk '$2 == "install.sh" || $2 == "*install.sh" {print tolower($1); exit}' "$tmp/checksums.txt")"
    [ -n "$want" ] || { echo "devbar: checksum di install.sh assente in checksums.txt" >&2; exit 1; }
    got="$(shasum -a 256 "$tmp/install.sh" | awk '{print tolower($1)}')"
    [ "$want" = "$got" ] || { echo "devbar: checksum di install.sh NON corrisponde: atteso $want, ottenuto $got" >&2; exit 1; }
    echo "devbar: checksum di install.sh verificato ($tag)" >&2
    CLAUDE_USAGE_VERSION="$tag" bash "$tmp/install.sh" </dev/null
  ) || rc=$?
  rm -rf "$tmp"
  return "$rc"
}
