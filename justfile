# devbar: comandi di sviluppo

default:
    @just --list

test:
    bats tests

# statusline/devbar-claude-statusline è escluso: copia verbatim da Sparkdock (vedi README).
lint:
    shellcheck -x -P SCRIPTDIR bin/devbar $(find lib -name '*.sh') scripts/install.sh app/bundle.sh

# XCTest manca nelle Command Line Tools: si usa swift-testing; il plugin macro va indicato a mano.
app-test:
    cd app && swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

app-build:
    cd app && swift build

# Assembla app/.build/devbar.app (release, firma ad-hoc).
build:
    cd app && swift build -c release
    app/bundle.sh

# Installa app, symlink ~/.local/bin/devbar e LaunchAgent. Il repo deve restare dov'è.
install: build
    scripts/install.sh install

uninstall:
    scripts/install.sh uninstall
