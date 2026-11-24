#!/usr/bin/env bash
# devbar: azioni colima/docker.

# _colima_valid_id <valore>: solo [A-Za-z0-9_.-], non vuoto, non inizia con '-'.
_colima_valid_id() {
  case "${1:-}" in
    '' | -* | *[!A-Za-z0-9_.-]*) return 1 ;;
  esac
}

# action_colima_start [profilo]
action_colima_start() {
  if [ $# -gt 0 ]; then
    _colima_valid_id "$1" || { echo "devbar: profilo non valido: $1" >&2; return 2; }
    colima start "$1"
  else
    colima start
  fi
}

# action_colima_stop [profilo]
action_colima_stop() {
  if [ $# -gt 0 ]; then
    _colima_valid_id "$1" || { echo "devbar: profilo non valido: $1" >&2; return 2; }
    colima stop "$1"
  else
    colima stop
  fi
}

# action_container_stop <id>
action_container_stop() {
  _colima_valid_id "${1:-}" || { echo "uso: devbar run container-stop <id>" >&2; return 2; }
  docker stop "$1"
}

# action_colima_install [--yes]: senza --yes stampa solo il piano.
action_colima_install() {
  if [ "${1:-}" != "--yes" ]; then
    echo "piano: brew install colima docker (rilancia con --yes per eseguire)"
    return 0
  fi
  brew install colima docker
}

# action_colima_logs <id>: `docker logs -f <id>` nel terminale.
action_colima_logs() {
  _colima_valid_id "${1:-}" || { echo "uso: devbar run colima-logs <id>" >&2; return 2; }
  open_in_terminal docker logs -f "$1"
}
