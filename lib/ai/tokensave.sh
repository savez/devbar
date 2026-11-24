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

ai_tokensave_install_cmds() {
  local h args=""
  for h in "$@"; do args="$args --agent $h"; done
  echo "tokensave install$args"
}

ai_tokensave_install() {
  local h args=()
  for h in "$@"; do args+=(--agent "$h"); done
  tokensave install "${args[@]}" </dev/null
}

ai_tokensave_tool_install_cmd() { echo "brew install aovestdipaperino/tap/tokensave"; }
ai_tokensave_tool_install() { brew install aovestdipaperino/tap/tokensave </dev/null; }
