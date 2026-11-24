#!/usr/bin/env bash
# devbar: azione caveman-mode (modalità di default del plugin caveman).

_caveman_mode_config() { printf '%s' "$HOME/.config/caveman/config.json"; }

# action_caveman_mode <off|manual|caveman|ultracave|megacave> [--yes]
# Senza --yes stampa solo il piano (JSON). Con --yes scrive `defaultMode` in
# ~/.config/caveman/config.json (altre chiavi preservate, file creato se manca).
# Passando a off ricorda l'ultima modalità attiva in `cavemanLastMode` (config devbar).
action_caveman_mode() {
  local mode="${1:-}" yes="${2:-}" cfg cur prev
  case "$mode" in
    off | manual | caveman | ultracave | megacave) ;;
    *) echo "uso: devbar run caveman-mode <off|manual|caveman|ultracave|megacave> [--yes]" >&2; return 2 ;;
  esac
  cfg="$(_caveman_mode_config)"
  if [ -e "$cfg" ] && ! jq -e 'type == "object"' "$cfg" >/dev/null 2>&1; then
    jq -nc --arg f "$cfg" '{status:"error",error:("config caveman non valida: " + $f)}'
    return 2
  fi
  local lines
  lines="$(jq -nc --arg m "$mode" '["Scrive defaultMode = \"" + $m + "\" in ~/.config/caveman/config.json", "vale per le nuove sessioni"]')"
  if [ "$yes" != "--yes" ]; then
    jq -nc --arg m "$mode" --argjson l "$lines" \
      '{plan:true, file:"~/.config/caveman/config.json", key:"defaultMode", value:$m, commands:$l}'
    return 0
  fi
  cur=""
  [ ! -f "$cfg" ] || cur="$(jq -r '.defaultMode // "" | tostring' "$cfg")"
  if [ "$mode" = off ]; then
    prev="$(_caveman_canonical_mode "$cur")"
    # shellcheck disable=SC2016 # $m è una variabile jq
    case "$prev" in
      off) ;;
      *) config_update '.cavemanLastMode = $m' --arg m "$prev" || return 2 ;;
    esac
  fi
  local base='{}'
  [ ! -f "$cfg" ] || base="$(cat "$cfg")"
  jq --arg m "$mode" '.defaultMode = $m' <<<"$base" | devbar_write_file "$cfg" || return 2
  jq -nc --arg m "$mode" --argjson l "$lines" '{applied:true, value:$m, commands:$l}'
}
