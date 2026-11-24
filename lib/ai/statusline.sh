#!/usr/bin/env bash
# devbar: AI setup per la statusline di Claude Code (vedi interfaccia in lib/ai/ai.sh).
# Logica di `enable` portata da github.com/sparkfabrik/sparkdock
# (sjust/scripts/claude-statusline.py, lib/claude_settings.py), GPLv3, in bash+jq.
# Differenza voluta: un settings.json non valido NON viene sostituito da {} (rc 2).

# Solo Claude Code ha una statusline configurabile.
ai_statusline_supports() { [ "$1" = claude ]; }

# "Installato" = Claude Code presente (il tool è una chiave di settings.json).
ai_statusline_installed() {
  command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]
}

# ai-status senza claude: rc 3 (non configurato / strumento assente).
ai_statusline_absent_rc() { echo 3; }

_statusline_settings() { printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; }
_statusline_script() { printf '%s' "$DEVBAR_ROOT/statusline/devbar-claude-statusline"; }
_statusline_command() { printf 'bash "%s"' "$(_statusline_script)"; }

# installed: punta al file di devbar; outdated: punta altrove; missing: nessuna statusline.
ai_statusline_state() {
  local f cur
  f="$(_statusline_settings)"
  [ -f "$f" ] || { echo missing; return 0; }
  cur="$(jq -r 'if (.statusLine | type) == "object" then (.statusLine.command // "" | tostring) else "" end' "$f" 2>/dev/null)" || cur=""
  if [ -z "$cur" ]; then echo missing
  elif [ "$cur" = "$(_statusline_command)" ]; then echo installed
  else echo outdated; fi
}

ai_statusline_install_cmds() {
  echo "backup di $(_statusline_settings) in settings.json.devbar-<timestamp> (se esiste)"
  echo "imposta .statusLine.command = $(_statusline_command) in $(_statusline_settings)"
}

ai_statusline_install() {
  local f cmd cur backup stamp n=0 new
  f="$(_statusline_settings)"
  cmd="$(_statusline_command)"
  [ -f "$(_statusline_script)" ] || { echo "devbar: statusline non trovata: $(_statusline_script)" >&2; return 1; }
  if [ -e "$f" ]; then
    if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
      echo "devbar: settings.json non valido: $f (non modificato)" >&2
      return 1
    fi
    cur="$(jq -r 'if (.statusLine | type) == "object" then (.statusLine.command // "" | tostring) else "" end' "$f")"
    if [ "$cur" = "$cmd" ]; then
      echo "devbar: statusline già abilitata in $f" >&2
      return 0
    fi
    [ -z "$cur" ] || echo "devbar: sostituisco statusLine esistente: $cur" >&2
    stamp="$(date +%Y%m%d%H%M%S)"
    backup="$f.devbar-$stamp"
    while [ -e "$backup" ]; do n=$((n + 1)); backup="$f.devbar-$stamp-$n"; done
    # cp -p: il backup eredita il modo (settings.json è spesso 600)
    journal_before "$backup" </dev/null || return 1
    cp -p "$f" "$backup" || return 1
    echo "devbar: backup in $backup" >&2
    new="$(jq --arg c "$cmd" '.statusLine = {type:"command",command:$c}' "$f")" || return 1
  else
    new="$(jq -n --arg c "$cmd" '{statusLine:{type:"command",command:$c}}')" || return 1
  fi
  printf '%s\n' "$new" | devbar_write_file "$f"
}
