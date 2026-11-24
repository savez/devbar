# devbar: comandi di sviluppo

default:
    @just --list

test:
    bats tests

lint:
    shellcheck -x -P SCRIPTDIR bin/devbar $(find lib -name '*.sh')

# XCTest manca nelle Command Line Tools: si usa swift-testing; il plugin macro va indicato a mano.
app-test:
    cd app && swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

app-build:
    cd app && swift build
