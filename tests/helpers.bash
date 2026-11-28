# Helper condivisi dai test bats di devbar.

DEVBAR_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVBAR_REPO

setup_env() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export DEVBAR_CONFIG="$BATS_TEST_TMPDIR/config.json"
  export DEVBAR_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export STUB_FIXTURES_DIR="$DEVBAR_REPO/tests/fixtures"
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  # curl è sempre uno stub che fallisce: nessun test fa rete (advisories scarica un feed).
  # File a sé, non un symlink: i test che scrivono il proprio curl non devono toccare tests/stubs/_stub.
  printf '#!/bin/sh\nexit 6\n' >"$BATS_TEST_TMPDIR/stubs/curl"
  chmod +x "$BATS_TEST_TMPDIR/stubs/curl"
  # stub per-test (make_stub) davanti, poi tests/stubs
  export PATH="$BATS_TEST_TMPDIR/stubs:$DEVBAR_REPO/tests/stubs:$PATH"
}

# make_stub <tool>...: crea lo stub <tool> (symlink a tests/stubs/_stub).
# Controllo via env: STUB_<TOOL>_FIXTURE (file in tests/fixtures/<tool>/),
# STUB_<TOOL>_RC (default 0), override per sottocomando
# STUB_<TOOL>_<SUBCMD>_FIXTURE / _RC. Chiamate in $BATS_TEST_TMPDIR/<tool>.calls.
make_stub() {
  local t
  for t in "$@"; do
    ln -sf "$DEVBAR_REPO/tests/stubs/_stub" "$BATS_TEST_TMPDIR/stubs/$t"
  done
}

# write_config '<json>': scrive il config di test.
write_config() { printf '%s\n' "$1" >"$DEVBAR_CONFIG"; }

# Esegue codice bash con lib/common.sh già caricato.
in_common() { bash -c "set -euo pipefail; source '$DEVBAR_REPO/lib/common.sh'; $1"; }

# schema_ok <schema> <json>: l'output è valido per schemas/<schema>.schema.json (check-jsonschema).
schema_ok() {
  local f="$BATS_TEST_TMPDIR/out.json"
  printf '%s\n' "$2" >"$f"
  check-jsonschema --schemafile "$DEVBAR_REPO/schemas/$1.schema.json" "$f"
}
