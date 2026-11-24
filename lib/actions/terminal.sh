#!/usr/bin/env bash
# devbar: apre un comando in un terminale (config .terminal).

# open_in_terminal <cmd> [args...]: ogni parola è quotata con printf %q.
open_in_terminal() {
  local cmd term esc
  cmd="$(printf '%q ' "$@")"
  cmd="${cmd% }"
  # escape per una stringa AppleScript tra doppi apici
  esc="${cmd//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  term="$(config_get .terminal)"
  case "$term" in
    iTerm | iTerm2)
      osascript -e 'tell application "iTerm" to activate' \
        -e "tell application \"iTerm\" to create window with default profile command \"$esc\"" ;;
    Ghostty)
      osascript -e 'tell application "Ghostty" to activate' \
        -e "tell application \"Ghostty\" to new window with configuration {command:\"$esc\"}" ;;
    *)
      osascript -e 'tell application "Terminal" to activate' \
        -e "tell application \"Terminal\" to do script \"$esc\"" ;;
  esac
}

# action_open_terminal <path>: apre il terminale nella cartella (deve esistere).
action_open_terminal() {
  [ -n "${1:-}" ] && [ -d "$1" ] || { echo "uso: devbar run open-terminal <cartella esistente>" >&2; return 2; }
  # iTerm e Ghostty: il comando È il processo della finestra, `cd` da solo uscirebbe
  # subito e la finestra si chiuderebbe: dopo il cd si resta in una shell di login.
  case "$(config_get .terminal)" in
    iTerm | iTerm2 | Ghostty)
      open_in_terminal sh -c "cd $(printf '%q' "$1") && exec \"\${SHELL:-/bin/zsh}\" -l" ;;
    *) open_in_terminal cd "$1" ;;
  esac
}
