#!/usr/bin/env bash
# devbar: AI setup per TokenEconomizer (vedi interfaccia in lib/ai/ai.sh).
# TokenEconomizer (github.com/microsoft/TokenEconomizer, Apache-2.0) è un plugin per gli harness:
# si clona il repo e per ogni harness si aggiunge il marketplace locale e si installa il plugin.

DEVBAR_TE_URL="https://github.com/microsoft/TokenEconomizer.git"
DEVBAR_TE_PLUGIN="tokeneconomizer@tokeneconomizer"

# te_default_dir: dove devbar clona se non c'è già un clone.
te_default_dir() { printf '%s' "${DEVBAR_TE_DIR:-$HOME/.local/share/devbar/TokenEconomizer}"; }

# te_clone_dir: percorso del clone (rc 1 se non c'è). Prima il marketplace locale già
# registrato in Claude Code, poi la cartella di devbar; vale solo con plugin/scripts/te.
te_clone_dir() {
  local mk d
  mk="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/known_marketplaces.json"
  if [ -f "$mk" ]; then
    d="$(jq -r '.tokeneconomizer.source | select(type == "object" and .source == "directory") | .path // empty' "$mk" 2>/dev/null || true)"
    if [ -n "$d" ] && [ -x "$d/plugin/scripts/te" ]; then printf '%s' "$d"; return 0; fi
  fi
  d="$(te_default_dir)"
  if [ -x "$d/plugin/scripts/te" ]; then printf '%s' "$d"; return 0; fi
  return 1
}

# te_bin: eseguibile `te` del clone (rc 1 se non c'è).
te_bin() {
  local d
  d="$(te_clone_dir)" || return 1
  printf '%s/plugin/scripts/te' "$d"
}

ai_tokeneconomizer_installed() { te_clone_dir >/dev/null; }

# Solo gli harness con installazione documentata nel README di TokenEconomizer.
ai_tokeneconomizer_supports() {
  case "$1" in claude | codex | copilot) return 0 ;; esac
  return 1
}

# Stato: claude da `claude plugin list --json` (plugin presente e abilitato);
# codex e copilot dal testo di `<cli> plugin list` (riga con l'id del plugin, non disabilitata).
# CLI assente o che fallisce: missing.
ai_tokeneconomizer_state() {
  local h="$1" out
  command -v "$h" >/dev/null 2>&1 || { echo missing; return 0; }
  case "$h" in
    claude)
      out="$(claude plugin list --json 2>/dev/null </dev/null || true)"
      if jq -e --arg id "$DEVBAR_TE_PLUGIN" 'any(.[]; .id == $id and .enabled == true)' <<<"$out" >/dev/null 2>&1; then
        echo installed
      else echo missing; fi
      ;;
    *)
      out="$("$h" plugin list 2>/dev/null </dev/null || true)"
      if grep -F "$DEVBAR_TE_PLUGIN" <<<"$out" | grep -qiv 'disabled'; then
        echo installed
      else echo missing; fi
      ;;
  esac
}

# _te_add_verb <harness>: verbo che installa il plugin (Codex usa `plugin add`).
_te_add_verb() { if [ "$1" = codex ]; then echo add; else echo install; fi; }

ai_tokeneconomizer_install_cmds() {
  local h clone
  clone="$(te_clone_dir || te_default_dir)"
  for h in "$@"; do
    echo "$h plugin marketplace add $clone"
    echo "$h plugin $(_te_add_verb "$h") $DEVBAR_TE_PLUGIN"
    echo "$h: questa modifica non si può annullare da devbar (la installa la CLI di $h; per toglierla: $h plugin uninstall $DEVBAR_TE_PLUGIN)"
    case "$h" in
      claude) echo "claude: dopo l'installazione apri Claude Code, fidati della cartella e lancia una volta /tokeneconomizer:toolprune refresh-catalog" ;;
      *) echo "$h: dopo l'installazione avvia $h e fidati della cartella, come scrive il README di TokenEconomizer" ;;
    esac
  done
}

ai_tokeneconomizer_install() {
  local h clone
  clone="$(te_clone_dir)" || { echo "devbar: clone di TokenEconomizer non trovato (usa AI setup, Init TokenEconomizer)" >&2; return 1; }
  for h in "$@"; do
    command -v "$h" >/dev/null 2>&1 || { echo "devbar: $h non trovato nel PATH" >&2; return 1; }
    # Un marketplace già aggiunto non è un errore: conta l'esito dell'install.
    "$h" plugin marketplace add "$clone" </dev/null || true
    "$h" plugin "$(_te_add_verb "$h")" "$DEVBAR_TE_PLUGIN" </dev/null || return 1
  done
}

ai_tokeneconomizer_tool_install_cmd() {
  local d
  if d="$(te_clone_dir)"; then
    echo "clone già presente in $d: nessuna azione"
  else
    echo "git clone --depth 1 $DEVBAR_TE_URL $(te_default_dir)"
  fi
}

ai_tokeneconomizer_tool_install() {
  te_clone_dir >/dev/null && return 0
  local d
  d="$(te_default_dir)"
  mkdir -p "$(dirname "$d")" || return 1
  git clone --depth 1 "$DEVBAR_TE_URL" "$d" </dev/null
}
