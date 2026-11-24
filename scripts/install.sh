#!/usr/bin/env bash
# devbar: install | uninstall dell'app e del LaunchAgent.
# Override per i test (nessuno è necessario in uso normale):
#   DEVBAR_INSTALL_HOME  radice dei percorsi (default $HOME)
#   DEVBAR_APP_SRC       bundle da installare (default: devbar.app accanto a questo script se c'è,
#                        cioè quando gira dallo zip di una release; altrimenti app/.build/devbar.app)
#   XATTR                binario xattr (default xattr)
#   LAUNCHCTL            binario launchctl (default /bin/launchctl)
#   PKILL                binario pkill (default pkill)
#   DEVBAR_UID           uid del dominio gui/ (default id -u)
# Non tocca mai ~/.config/devbar.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
home="${DEVBAR_INSTALL_HOME:-$HOME}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$here/devbar.app" ]; then default_src="$here/devbar.app"; else default_src="$repo/app/.build/devbar.app"; fi
src_app="${DEVBAR_APP_SRC:-$default_src}"
xattr_bin="${XATTR:-xattr}"
launchctl_bin="${LAUNCHCTL:-/bin/launchctl}"
pkill_bin="${PKILL:-pkill}"
uid="${DEVBAR_UID:-$(id -u)}"
label="it.savez.devbar"
domain="gui/$uid"

app_dir="$home/Applications/devbar.app"
exe="$app_dir/Contents/MacOS/Devbar"
engine_bin="$app_dir/Contents/Resources/engine/bin/devbar"
link="$home/.local/bin/devbar"
plist="$home/Library/LaunchAgents/$label.plist"

# regex_escape <testo>: escape dei metacaratteri di una regex estesa.
regex_escape() { printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'; }

unload() {
  if "$launchctl_bin" print "$domain/$label" >/dev/null 2>&1; then
    "$launchctl_bin" bootout "$domain/$label" >/dev/null 2>&1 || true
  fi
}

install() {
  [ -x "$src_app/Contents/MacOS/Devbar" ] || { echo "devbar: bundle assente: $src_app (esegui 'just build')" >&2; exit 1; }
  [ -x "$src_app/Contents/Resources/engine/bin/devbar" ] || { echo "devbar: motore assente nel bundle: $src_app" >&2; exit 1; }

  mkdir -p "$home/Applications" "$home/.local/bin" "$home/Library/LaunchAgents"

  # Ferma il vecchio job prima di sostituire il bundle.
  unload

  # Sostituzione del bundle: copia accanto, poi due rename.
  rm -rf "$app_dir.new" "$app_dir.old"
  cp -R "$src_app" "$app_dir.new"
  if [ -e "$app_dir" ]; then mv "$app_dir" "$app_dir.old"; fi
  mv "$app_dir.new" "$app_dir"
  rm -rf "$app_dir.old"

  # Firma ad-hoc, non notarizzata: un bundle scaricato porta la quarantena e Gatekeeper lo rifiuterebbe.
  "$xattr_bin" -dr com.apple.quarantine "$app_dir" >/dev/null 2>&1 || true

  ln -sfn "$engine_bin" "$link"

  # Una sola fonte del plist: DevbarCore.LaunchAgent, chiesto al binario installato.
  "$exe" --print-launch-agent-plist "$exe" >"$plist.tmp"
  mv "$plist.tmp" "$plist"

  # Eventuale istanza avviata a mano: la guardia di istanza unica farebbe uscire quella nuova.
  # Pattern ancorato all'eseguibile esatto (metacaratteri regex escapati).
  "$pkill_bin" -f "^$(regex_escape "$exe")( |\$)" >/dev/null 2>&1 || true
  "$launchctl_bin" bootstrap "$domain" "$plist"
  echo "devbar installato: $app_dir"
}

uninstall() {
  unload
  rm -f "$plist"
  rm -rf "$app_dir"
  # Solo se è il nostro symlink: motore nel bundle, o (vecchie installazioni) bin/devbar del repo.
  if [ -L "$link" ]; then
    target="$(readlink "$link")"
    if [ "$target" = "$engine_bin" ] || [ "$target" = "$repo/bin/devbar" ]; then rm -f "$link"; fi
  fi
  echo "devbar rimosso (config in ~/.config/devbar intatta)"
}

case "${1:-}" in
  install) install ;;
  uninstall) uninstall ;;
  *) echo "uso: install.sh install|uninstall" >&2; exit 2 ;;
esac
