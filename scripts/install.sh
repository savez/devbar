#!/usr/bin/env bash
# devbar: install | uninstall dell'app e del LaunchAgent.
# Override per i test (nessuno è necessario in uso normale):
#   DEVBAR_INSTALL_HOME  radice dei percorsi (default $HOME)
#   DEVBAR_APP_SRC       bundle da installare (default app/.build/devbar.app)
#   LAUNCHCTL            binario launchctl (default /bin/launchctl)
#   PKILL                binario pkill (default pkill)
#   DEVBAR_UID           uid del dominio gui/ (default id -u)
# Non tocca mai ~/.config/devbar.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
home="${DEVBAR_INSTALL_HOME:-$HOME}"
src_app="${DEVBAR_APP_SRC:-$repo/app/.build/devbar.app}"
launchctl_bin="${LAUNCHCTL:-/bin/launchctl}"
pkill_bin="${PKILL:-pkill}"
uid="${DEVBAR_UID:-$(id -u)}"
label="it.savez.devbar"
domain="gui/$uid"

app_dir="$home/Applications/devbar.app"
exe="$app_dir/Contents/MacOS/Devbar"
link="$home/.local/bin/devbar"
plist="$home/Library/LaunchAgents/$label.plist"

unload() {
  if "$launchctl_bin" print "$domain/$label" >/dev/null 2>&1; then
    "$launchctl_bin" bootout "$domain/$label" >/dev/null 2>&1 || true
  fi
}

install() {
  [ -x "$src_app/Contents/MacOS/Devbar" ] || { echo "devbar: bundle assente: $src_app (esegui 'just build')" >&2; exit 1; }
  [ -x "$repo/bin/devbar" ] || { echo "devbar: bin/devbar assente in $repo" >&2; exit 1; }

  mkdir -p "$home/Applications" "$home/.local/bin" "$home/Library/LaunchAgents"

  # Ferma il vecchio job prima di sostituire il bundle.
  unload

  # Sostituzione del bundle: copia accanto, poi due rename.
  rm -rf "$app_dir.new" "$app_dir.old"
  cp -R "$src_app" "$app_dir.new"
  if [ -e "$app_dir" ]; then mv "$app_dir" "$app_dir.old"; fi
  mv "$app_dir.new" "$app_dir"
  rm -rf "$app_dir.old"

  ln -sfn "$repo/bin/devbar" "$link"

  # Una sola fonte del plist: DevbarCore.LaunchAgent, chiesto al binario installato.
  "$exe" --print-launch-agent-plist "$exe" >"$plist.tmp"
  mv "$plist.tmp" "$plist"

  # Eventuale istanza avviata a mano: la guardia di istanza unica farebbe uscire quella nuova.
  "$pkill_bin" -f "$exe" >/dev/null 2>&1 || true
  "$launchctl_bin" bootstrap "$domain" "$plist"
  echo "devbar installato: $app_dir"
}

uninstall() {
  unload
  rm -f "$plist"
  rm -rf "$app_dir"
  # Solo se è il nostro symlink.
  if [ -L "$link" ]; then rm -f "$link"; fi
  echo "devbar rimosso (config in ~/.config/devbar intatta)"
}

case "${1:-}" in
  install) install ;;
  uninstall) uninstall ;;
  *) echo "uso: install.sh install|uninstall" >&2; exit 2 ;;
esac
