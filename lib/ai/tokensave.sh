#!/usr/bin/env bash
# devbar: AI setup per tokensave (vedi interfaccia in lib/ai/ai.sh).

ai_tokensave_installed() { command -v tokensave >/dev/null 2>&1; }

# Id supportati = lista `tokensave install --help`, ristretta agli harness di devbar.
ai_tokensave_supports() {
  case "$1" in claude | opencode | codex | gemini | copilot | cursor) return 0 ;; esac
  return 1
}

# Stato da `tokensave doctor --agent <id>`, sezione "<Agente> integration":
#   solo ✔ -> installed; ✔ e ✘ (es. MCP ok, regole mancanti) -> outdated;
#   solo ✘ o nessun ✔ (righe "!" = non trovato) -> missing.
# Le righe "!" sono varianti opzionali e non contano.
ai_tokensave_state() {
  local out ok bad
  out="$(tokensave doctor --agent "$1" 2>&1 </dev/null | sed $'s/\x1b\\[[0-9;]*m//g' |
    awk '/integration$/ {p=1; next} p && /^[[:space:]]*$/ {exit} p')" || out=""
  ok="$(grep -c '✔' <<<"$out" || true)"
  bad="$(grep -c '✘' <<<"$out" || true)"
  if [ "$ok" -gt 0 ] && [ "$bad" -gt 0 ]; then
    echo outdated
  elif [ "$ok" -gt 0 ]; then
    echo installed
  else
    echo missing
  fi
}

# _tokensave_install_paths <agente>: file che `tokensave install --agent` scrive, dai percorsi
# che `tokensave doctor --agent <agente>` controlla (uno per riga). rc 1 se non noti.
# ~/.claude.json escluso: Claude Code lo riscrive a ogni sessione, e un undo riporterebbe
# indietro anche il suo stato (vedi _tokensave_unjournaled_paths).
_tokensave_install_paths() {
  case "$1" in
    claude) printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" \
      "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rules/tokensave.md" ;;
    opencode) printf '%s\n' "$HOME/.config/opencode/opencode.json" "$HOME/.config/opencode/AGENTS.md" ;;
    codex) printf '%s\n' "$HOME/.codex/config.toml" "$HOME/.codex/AGENTS.md" ;;
    gemini) printf '%s\n' "$HOME/.gemini/settings.json" "$HOME/.gemini/GEMINI.md" ;;
    copilot) printf '%s\n' "$HOME/Library/Application Support/Code/User/mcp.json" \
      "$HOME/.copilot/mcp-config.json" "$HOME/.copilot/copilot-instructions.md" ;;
    cursor) printf '%s\n' "$HOME/.cursor/mcp.json" "$HOME/.cursor/hooks.json" ;;
    *) return 1 ;;
  esac
}

# _tokensave_unjournaled_paths <agente>: file scritti da tokensave che devbar non registra.
_tokensave_unjournaled_paths() {
  case "$1" in
    claude) printf '%s\n' "$HOME/.claude.json" ;;
    *) return 1 ;;
  esac
}

ai_tokensave_install_cmds() {
  local h args="" p
  for h in "$@"; do args="$args --agent $h"; done
  echo "tokensave install$args"
  for h in "$@"; do
    if p="$(_tokensave_install_paths "$h")"; then
      echo "$h: annullabile da Impostazioni (Ultime modifiche) per $(tr '\n' ',' <<<"$p" | sed "s#$HOME#~#g; s/,$//; s/,/, /g")"
    else
      echo "$h: questa modifica non si può annullare da devbar (file scritti da tokensave non noti)"
    fi
    if p="$(_tokensave_unjournaled_paths "$h")"; then
      echo "$h: questa modifica non si può annullare da devbar per $(tr '\n' ',' <<<"$p" | sed "s#$HOME#~#g; s/,$//; s/,/, /g") (riscritto da Claude Code a ogni sessione)"
    fi
  done
}

ai_tokensave_install() {
  local h args=() paths=() p
  for h in "$@"; do
    args+=(--agent "$h")
    while IFS= read -r p; do paths+=("$p"); done < <(_tokensave_install_paths "$h" || true)
  done
  # tokensave scrive da sé: si registra prima lo stato dei file noti (lib/journal.sh)
  journal_before ${paths[@]+"${paths[@]}"} </dev/null || return 1
  tokensave install "${args[@]}" </dev/null
}

ai_tokensave_tool_install_cmd() { echo "brew install aovestdipaperino/tap/tokensave"; }
ai_tokensave_tool_install() { brew install aovestdipaperino/tap/tokensave </dev/null; }
