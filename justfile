# devbar: comandi di sviluppo

default:
    @just --list

test:
    bats tests

lint:
    shellcheck -x -P SCRIPTDIR bin/devbar $(find lib -name '*.sh')
