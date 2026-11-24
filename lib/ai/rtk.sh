#!/usr/bin/env bash
# devbar: AI setup per RTK (vedi interfaccia in lib/ai/ai.sh).

ai_rtk_installed() { command -v rtk >/dev/null 2>&1; }

ai_rtk_supports() {
  case "$1" in claude | opencode | copilot | cursor) return 0 ;; esac
  return 1
}

# _rtk_show: `rtk init --show` senza escape ANSI.
_rtk_show() { rtk init --show 2>/dev/null </dev/null | sed $'s/\x1b\\[[0-9;]*m//g'; }

# Stato: claude/opencode/cursor da `rtk init --show` ([ok] sulla riga giusta);
# copilot dal blocco gestito in ~/.copilot/copilot-instructions.md.
# outdated: copilot se il blocco differisce dal testo corrente; opencode 2.x se
# il plugin installato differisce dalla patch. Per claude/cursor non rilevabile
# in modo affidabile: solo installed|missing.
ai_rtk_state() {
  local show
  case "$1" in
    claude)
      show="$(_rtk_show)"
      if grep -q '^\[ok\] Hook:' <<<"$show" && grep -q '^\[ok\] settings.json' <<<"$show"; then
        echo installed
      else echo missing; fi
      ;;
    opencode)
      show="$(_rtk_show)"
      if ! grep -q '^\[ok\] OpenCode:' <<<"$show"; then
        echo missing
      elif _rtk_opencode_plugin_stale; then
        echo outdated
      else echo installed; fi
      ;;
    cursor)
      if _rtk_show | grep -q '^\[ok\] Cursor hook'; then echo installed; else echo missing; fi
      ;;
    copilot) _rtk_copilot_state ;;
    *) echo missing ;;
  esac
}

ai_rtk_install_cmds() {
  local h
  for h in "$@"; do
    case "$h" in
      claude) echo "rtk init -g --auto-patch" ;;
      opencode)
        echo "rtk init -g --opencode --auto-patch"
        echo "cp <devbar>/lib/ai/patches/opencode-plugin.ts ~/.config/opencode/plugins/rtk.ts (solo OpenCode >= 2)"
        ;;
      copilot)
        echo "scrivi il blocco RTK in ~/.copilot/copilot-instructions.md"
        echo "installa ~/.local/bin/rtk-run"
        ;;
      cursor) echo "rtk init -g --agent cursor" ;;
    esac
  done
}

ai_rtk_install() {
  local h
  for h in "$@"; do
    case "$h" in
      claude) rtk init -g --auto-patch </dev/null || return 1 ;;
      opencode)
        rtk init -g --opencode --auto-patch </dev/null || return 1
        _rtk_patch_opencode_plugin || return 1
        ;;
      copilot) _rtk_setup_copilot || return 1 ;;
      cursor) rtk init -g --agent cursor </dev/null || return 1 ;;
    esac
  done
}

ai_rtk_tool_install_cmd() { echo "brew install rtk-ai/tap/rtk"; }
ai_rtk_tool_install() { brew install rtk-ai/tap/rtk </dev/null; }

# --- Copilot ---
# Portato da github.com/sparkfabrik/sparkdock (sjust/scripts/rtk/setup.sh), GPLv3
# (inject_with_markers, setup_copilot, install_rtk_run).

_RTK_MARKER_BEGIN="<!-- BEGIN RTK MANAGED BLOCK -->"
_RTK_MARKER_END="<!-- END RTK MANAGED BLOCK -->"

_rtk_copilot_instructions() {
  cat <<'TXT'
Use `rtk-run` for high-output local shell commands such as build, test, lint, search, status, diff, log, and package manager commands.

For commands with pipes, chains, or redirects, pass the whole command as one quoted string to `rtk-run`.

If unsure, run the raw command.
TXT
}

# _rtk_strip_block <file>: stampa il file senza il blocco gestito.
_rtk_strip_block() {
  awk -v begin="$_RTK_MARKER_BEGIN" -v end="$_RTK_MARKER_END" '
    $0 ~ begin { skip=1; next }
    $0 ~ end   { skip=0; next }
    !skip
  ' "$1"
}

# _rtk_inject_with_markers <file> <contenuto>: sostituisce/aggiunge il blocco.
_rtk_inject_with_markers() { inject_block "$1" "$_RTK_MARKER_BEGIN" "$_RTK_MARKER_END" "$2"; }

_rtk_copilot_file() { printf '%s' "$HOME/.copilot/copilot-instructions.md"; }

_rtk_copilot_state() {
  local f cur
  f="$(_rtk_copilot_file)"
  if [ -f "$f" ] && grep -q "$_RTK_MARKER_BEGIN" "$f" 2>/dev/null; then
    cur="$(awk -v begin="$_RTK_MARKER_BEGIN" -v end="$_RTK_MARKER_END" '
      $0 ~ begin { p=1; next } $0 ~ end { p=0 } p' "$f")"
    if [ "$cur" = "$(_rtk_copilot_instructions)" ]; then echo installed; else echo outdated; fi
  else
    echo missing
  fi
}

# rtk-run viene dalla copia in lib/ai (niente clone Sparkdock a runtime).
_rtk_install_run_helper() {
  local src="$DEVBAR_ROOT/lib/ai/rtk-run" dir="$HOME/.local/bin"
  [ -f "$src" ] || { echo "devbar: helper rtk-run non trovato: $src" >&2; return 1; }
  devbar_write_file "$dir/rtk-run" <"$src" || return 1
  chmod 0755 "$dir/rtk-run"
}

_rtk_setup_copilot() {
  local f orphan
  f="$(_rtk_copilot_file)"
  _rtk_install_run_helper || return 1
  if [ -L "$f" ]; then
    echo "devbar: $f è un symlink ($(readlink "$f")): salto (gestito altrove)" >&2
  else
    _rtk_inject_with_markers "$f" "$(_rtk_copilot_instructions)" || return 1
  fi
  # pulizia del vecchio ~/.github/copilot-instructions.md (mai documentato da GitHub)
  orphan="$HOME/.github/copilot-instructions.md"
  if [ -f "$orphan" ] && [ ! -L "$orphan" ] && grep -q "$_RTK_MARKER_BEGIN" "$orphan" 2>/dev/null; then
    _rtk_strip_block "$orphan" | devbar_write_file "$orphan" || return 1
  fi
}

# --- OpenCode ---
# Portato da github.com/sparkfabrik/sparkdock (sjust/scripts/rtk/setup.sh), GPLv3
# (opencode_major_version, patch_opencode_plugin).

# Major version di OpenCode, 0 se assente o senza versione.
_rtk_opencode_major_version() {
  local version
  if ! command -v opencode >/dev/null 2>&1; then
    echo 0
    return 0
  fi
  version="$(opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n 1 | cut -d. -f1 || true)"
  case "$version" in
    '' | *[!0-9]*) echo 0 ;;
    *) echo "$version" ;;
  esac
}

# `rtk init --opencode` scrive un plugin 1.x che OpenCode 2.x rifiuta
# (https://github.com/rtk-ai/rtk/issues/3898): lo sostituisce con la versione 2.x.
_rtk_patch_opencode_plugin() {
  local patch="$DEVBAR_ROOT/lib/ai/patches/opencode-plugin.ts"
  local dest="$HOME/.config/opencode/plugins/rtk.ts"
  [ "$(_rtk_opencode_major_version)" -ge 2 ] || return 0
  [ -f "$patch" ] || { echo "devbar: patch plugin OpenCode non trovata: $patch" >&2; return 0; }
  [ -f "$dest" ] || { echo "devbar: plugin OpenCode non trovato: $dest" >&2; return 0; }
  cmp -s "$patch" "$dest" && return 0
  devbar_write_file "$dest" <"$patch" || return 1
  echo "devbar: applicata patch plugin OpenCode 2.x a $dest (rtk#3898)" >&2
}

# _rtk_opencode_plugin_stale: rc 0 se OpenCode >= 2 e il plugin differisce dalla patch.
_rtk_opencode_plugin_stale() {
  local patch="$DEVBAR_ROOT/lib/ai/patches/opencode-plugin.ts"
  local dest="$HOME/.config/opencode/plugins/rtk.ts"
  [ "$(_rtk_opencode_major_version)" -ge 2 ] || return 1
  [ -f "$patch" ] && [ -f "$dest" ] && ! cmp -s "$patch" "$dest"
}
