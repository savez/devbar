.PHONY: test lint

test:
	bats tests

lint:
	shellcheck -x -P SCRIPTDIR bin/devbar $$(find lib -name '*.sh')
