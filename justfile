# devbar: comandi di sviluppo

default:
    @just --list

# Include tests/contract.bats (schemi in schemas/ contro l'output del motore, e deriva delle fixture).
test:
    bats tests

# Rigenera le fixture di contratto (app/Tests/DevbarCoreTests/Fixtures/contract) dal motore con gli stub,
# poi le valida contro schemas/. Dopo una modifica all'output del motore: just contract e commit.
contract:
    tests/contract-fixtures.sh
    bats tests/contract.bats

# Registra l'output reale degli strumenti in tests/fixtures/real (solo comandi di lettura, anonimizzato).
record-fixtures:
    scripts/record-fixtures.sh

# statusline/devbar-claude-statusline è escluso: copia verbatim da Sparkdock (vedi README).
lint:
    shellcheck -x -P SCRIPTDIR bin/devbar $(find lib -name '*.sh') scripts/install.sh app/bundle.sh tests/contract-fixtures.sh scripts/record-fixtures.sh

# XCTest manca nelle Command Line Tools: si usa swift-testing; il plugin macro va indicato a mano.
app-test:
    cd app && swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

app-build:
    cd app && swift build

# Istantanee PNG di pannello e Dettagli dalle fixture (nessuna chiamata alla CLI). dir relativa ad app/.
app-snapshots dir=".build/snapshots":
    cd app && swift build && .build/debug/Devbar --render-snapshots {{dir}} Tests/DevbarCoreTests/Fixtures

# Assembla app/.build/devbar.app (release, firma ad-hoc).
build:
    cd app && swift build -c release
    app/bundle.sh

# Installa app, symlink ~/.local/bin/devbar e LaunchAgent. Il repo deve restare dov'è.
install: build
    scripts/install.sh install

uninstall:
    scripts/install.sh uninstall
