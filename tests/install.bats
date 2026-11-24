#!/usr/bin/env bats
# scripts/install.sh con HOME temporaneo e launchctl finto: niente di reale viene toccato.

load helpers

setup() {
  setup_env
  export DEVBAR_INSTALL_HOME="$HOME"
  export DEVBAR_UID=501
  export PKILL=true
  export CALLS="$BATS_TEST_TMPDIR/launchctl.calls"
  : >"$CALLS"
  # launchctl finto: registra gli argomenti; "print" riesce se $FAKE_LOADED=1.
  cat >"$BATS_TEST_TMPDIR/launchctl" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$CALLS"
if [ "$1" = print ]; then [ "${FAKE_LOADED:-0}" = 1 ]; exit; fi
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/launchctl"
  export LAUNCHCTL="$BATS_TEST_TMPDIR/launchctl"
  # bundle finto: l'eseguibile stampa un plist per --print-launch-agent-plist.
  export DEVBAR_APP_SRC="$BATS_TEST_TMPDIR/src/devbar.app"
  mkdir -p "$DEVBAR_APP_SRC/Contents/MacOS"
  cat >"$DEVBAR_APP_SRC/Contents/MacOS/Devbar" <<'SH'
#!/usr/bin/env bash
[ "$1" = --print-launch-agent-plist ] && echo "<plist>$2</plist>"
SH
  chmod +x "$DEVBAR_APP_SRC/Contents/MacOS/Devbar"
  # motore nel bundle, come lo assembla app/bundle.sh
  mkdir -p "$DEVBAR_APP_SRC/Contents/Resources/engine"
  cp -R "$DEVBAR_REPO/bin" "$DEVBAR_REPO/lib" "$DEVBAR_REPO/statusline" "$DEVBAR_APP_SRC/Contents/Resources/engine/"
  mkdir -p "$HOME/.config/devbar"; echo '{}' >"$HOME/.config/devbar/config.json"
}

@test "install copia il bundle, crea symlink e plist, fa bootstrap" {
  run "$DEVBAR_REPO/scripts/install.sh" install
  [ "$status" -eq 0 ]
  [ -x "$HOME/Applications/devbar.app/Contents/MacOS/Devbar" ]
  [ "$(readlink "$HOME/.local/bin/devbar")" = "$HOME/Applications/devbar.app/Contents/Resources/engine/bin/devbar" ]
  grep -q "$HOME/Applications/devbar.app/Contents/MacOS/Devbar" "$HOME/Library/LaunchAgents/it.savez.devbar.plist"
  grep -q "^bootstrap gui/501 $HOME/Library/LaunchAgents/it.savez.devbar.plist$" "$CALLS"
  [ "$(grep -c '^bootout' "$CALLS" || true)" -eq 0 ]
}

@test "install con job già caricato fa bootout prima di bootstrap e sostituisce il bundle" {
  mkdir -p "$HOME/Applications/devbar.app/Contents"; touch "$HOME/Applications/devbar.app/Contents/vecchio"
  FAKE_LOADED=1 run "$DEVBAR_REPO/scripts/install.sh" install
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Applications/devbar.app/Contents/vecchio" ]
  [ ! -e "$HOME/Applications/devbar.app.old" ]
  [ "$(grep -n '^bootout\|^bootstrap' "$CALLS" | cut -d: -f2 | cut -d' ' -f1 | paste -sd, -)" = "bootout,bootstrap" ]
  grep -q '^bootout gui/501/it.savez.devbar$' "$CALLS"
}

@test "install: devbar check lanciato dal link funziona col motore nel bundle" {
  run "$DEVBAR_REPO/scripts/install.sh" install
  [ "$status" -eq 0 ]
  run "$HOME/.local/bin/devbar" version
  [ "$status" -eq 0 ]
  run "$HOME/.local/bin/devbar" check harnesses
  [ "$status" -eq 0 ]
  echo "$output" | jq -e .status >/dev/null
  # il motore usato è quello copiato nel bundle, non il repo
  [ -f "$HOME/Applications/devbar.app/Contents/Resources/engine/lib/common.sh" ]
}

@test "install eseguito da uno zip (devbar.app accanto allo script) installa quel bundle" {
  zipdir="$BATS_TEST_TMPDIR/zip"; mkdir -p "$zipdir"
  cp -R "$DEVBAR_APP_SRC" "$zipdir/devbar.app"; cp "$DEVBAR_REPO/scripts/install.sh" "$zipdir/install.sh"
  unset DEVBAR_APP_SRC
  run "$zipdir/install.sh" install
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.local/bin/devbar")" = "$HOME/Applications/devbar.app/Contents/Resources/engine/bin/devbar" ]
  run "$HOME/.local/bin/devbar" version
  [ "$status" -eq 0 ]
}

@test "install rimuove la quarantena dal bundle installato" {
  cat >"$BATS_TEST_TMPDIR/xattr" <<'SH'
#!/usr/bin/env bash
echo "$*" >"$BATS_TEST_TMPDIR/xattr.args"
SH
  chmod +x "$BATS_TEST_TMPDIR/xattr"
  XATTR="$BATS_TEST_TMPDIR/xattr" run "$DEVBAR_REPO/scripts/install.sh" install
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/xattr.args")" = "-dr com.apple.quarantine $HOME/Applications/devbar.app" ]
}

@test "uninstall rimuove anche il vecchio symlink verso il repo" {
  mkdir -p "$HOME/.local/bin"; ln -s "$DEVBAR_REPO/bin/devbar" "$HOME/.local/bin/devbar"
  run "$DEVBAR_REPO/scripts/install.sh" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/devbar" ]
}

@test "install senza bundle fallisce con messaggio" {
  DEVBAR_APP_SRC="$BATS_TEST_TMPDIR/nope.app" run "$DEVBAR_REPO/scripts/install.sh" install
  [ "$status" -eq 1 ]
  [[ "$output" == *"just build"* ]]
}

@test "uninstall rimuove app, symlink, plist e fa bootout, lascia la config" {
  "$DEVBAR_REPO/scripts/install.sh" install
  : >"$CALLS"
  FAKE_LOADED=1 run "$DEVBAR_REPO/scripts/install.sh" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Applications/devbar.app" ]
  [ ! -e "$HOME/.local/bin/devbar" ]
  [ ! -e "$HOME/Library/LaunchAgents/it.savez.devbar.plist" ]
  grep -q '^bootout gui/501/it.savez.devbar$' "$CALLS"
  [ -f "$HOME/.config/devbar/config.json" ]
}

@test "uninstall senza nulla installato riesce" {
  run "$DEVBAR_REPO/scripts/install.sh" uninstall
  [ "$status" -eq 0 ]
}

@test "bin/devbar risolve DEVBAR_ROOT via symlink" {
  mkdir -p "$HOME/.local/bin"; ln -s "$DEVBAR_REPO/bin/devbar" "$HOME/.local/bin/devbar"
  run "$HOME/.local/bin/devbar" version
  [ "$status" -eq 0 ]
}

@test "uninstall: ~/.local/bin/devbar che punta altrove non viene rimosso" {
  mkdir -p "$HOME/.local/bin"
  ln -s /usr/bin/true "$HOME/.local/bin/devbar"
  run "$DEVBAR_REPO/scripts/install.sh" uninstall
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/devbar" ]
  [ "$(readlink "$HOME/.local/bin/devbar")" = /usr/bin/true ]
}

@test "install: pkill con pattern ancorato all'eseguibile, punti escapati" {
  cat >"$BATS_TEST_TMPDIR/pkill" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/pkill.args"
exit 1
SH
  chmod +x "$BATS_TEST_TMPDIR/pkill"
  PKILL="$BATS_TEST_TMPDIR/pkill" run "$DEVBAR_REPO/scripts/install.sh" install
  [ "$status" -eq 0 ]
  pat="$(sed -n 2p "$BATS_TEST_TMPDIR/pkill.args")"
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/pkill.args")" = -f ]
  [[ "$pat" == "^"* ]]
  [[ "$pat" == *'devbar\.app/Contents/MacOS/Devbar( |$)' ]]
  exe="$HOME/Applications/devbar.app/Contents/MacOS/Devbar"
  [[ "$exe" =~ $pat ]]
  [[ "$exe --altro" =~ $pat ]]
  [[ ! "${exe}2" =~ $pat ]]
  [[ ! "/x$exe" =~ $pat ]]
}

@test "install.sh senza argomenti installa (come scritto nel README)" {
  run "$DEVBAR_REPO/scripts/install.sh"
  [ "$status" -eq 0 ]
  [ -x "$HOME/Applications/devbar.app/Contents/MacOS/Devbar" ]
}
