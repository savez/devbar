#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_env
  make_stub curl
  DEVBAR="$DEVBAR_REPO/bin/devbar"
  export LC_ALL=C
}

# date_ago <giorni>: data RFC 822 in UTC, N giorni fa.
date_ago() { date -u -v-"$1"d "+%a, %d %b %Y %H:%M:%S +0000"; }

# make_feed [<data-di-e>]: feed di prova con date relative, servito dallo stub di curl.
make_feed() {
  local fx="$BATS_TEST_TMPDIR/fx"
  mkdir -p "$fx/curl"
  sed -e "s/@DATE_a@/$(date_ago "${A_DAYS:-1}")/" -e "s/@DATE_b@/$(date_ago 2)/" \
    -e "s/@DATE_c@/$(date_ago 30)/" -e "s/@DATE_d@/$(date_ago "${D_DAYS:-1}")/" \
    -e "s/@DATE_e@/${1:-$(date_ago 3)}/" \
    "$DEVBAR_REPO/tests/fixtures/advisories/feed.xml" >"$fx/curl/feed.xml"
  export STUB_FIXTURES_DIR="$fx" STUB_CURL_FIXTURE=feed.xml
}

@test "advisories: voci recenti, count e rc" {
  make_feed
  run --separate-stderr "$DEVBAR" check advisories
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<<"$output")" = action ]
  [ "$(jq -r .count <<<"$output")" = 2 ]
  [ "$(jq -r '.items|length' <<<"$output")" = 4 ]
  [ "$(jq -r '.items[]|select(.package=="vendor/pkg").severity' <<<"$output")" = CRITICAL ]
  [ "$(jq -r '.items[]|select(.package=="vendor/pkg").score' <<<"$output")" = 9.1 ]
  [ "$(jq -r '.items[]|select(.package=="vendor/pkg").ecosystem' <<<"$output")" = composer ]
  [ "$(jq -r '.items[]|select(.package=="vendor/pkg").id' <<<"$output")" = CVE-2026-1111 ]
  [ "$(jq -r '.items[]|select(.package=="vendor/pkg").source' <<<"$output")" = "GitHub Advisory DB" ]
  [ "$(jq -r '[.items[]|select(.package=="old/pkg")]|length' <<<"$output")" = 0 ]
  [ "$(jq -r '.items[]|select(.severity=="ALERT").ecosystem' <<<"$output")" = alert ]
}

@test "advisories: nessuna voce grave recente -> rc 1" {
  # a e d (le gravi) fuori dalla finestra di 7 giorni: restano solo b ed e
  A_DAYS=40 D_DAYS=40 make_feed
  run --separate-stderr "$DEVBAR" check advisories
  [ "$status" -eq 1 ]
  [ "$(jq -r .status <<<"$output")" = ok ]
  [ "$(jq -r .count <<<"$output")" = 0 ]
}

@test "advisories: titolo senza formato -> UNKNOWN" {
  make_feed
  run --separate-stderr "$DEVBAR" check advisories
  [ "$(jq -r '.items[]|select(.title=="Titolo senza formato").severity' <<<"$output")" = UNKNOWN ]
  [ "$(jq -r '.items[]|select(.title=="Titolo senza formato").package' <<<"$output")" = "" ]
}

@test "advisories: pubDate illeggibile -> voce scartata" {
  make_feed "non è una data"
  run --separate-stderr "$DEVBAR" check advisories
  [ "$status" -eq 0 ]
  [ "$(jq -r '.items|length' <<<"$output")" = 3 ]
}

@test "advisories: advisoriesDays non valido torna a 7" {
  make_feed
  local v
  for v in 0 '"x"' -3; do
    write_config "{\"advisoriesDays\":$v}"
    rm -rf "$DEVBAR_CACHE_DIR"
    run --separate-stderr "$DEVBAR" check advisories
    [ "$(jq -r .count <<<"$output")" = 2 ]
    [[ "$(jq -r .summary <<<"$output")" == *"7 giorni"* ]]
  done
}

@test "advisories: rete assente con cache -> usa la cache" {
  make_feed
  run --separate-stderr "$DEVBAR" check advisories
  [ "$status" -eq 0 ]
  export STUB_CURL_RC=6 STUB_CURL_FIXTURE=
  touch -t 202001010000 "$DEVBAR_CACHE_DIR/advisories.json"
  run --separate-stderr "$DEVBAR" check advisories
  [ "$status" -eq 0 ]
  [ "$(jq -r .count <<<"$output")" = 2 ]
  [[ "$stderr" == *cache* ]]
}

@test "advisories: rete assente senza cache -> rc 2" {
  export STUB_CURL_RC=6
  run --separate-stderr "$DEVBAR" check advisories
  [ "$status" -eq 2 ]
  [ "$(jq -r .status <<<"$output")" = error ]
}

@test "advisories: XML rotto -> rc 2" {
  make_feed
  printf '<rss><channel><item>' >"$STUB_FIXTURES_DIR/curl/feed.xml"
  run --separate-stderr "$DEVBAR" check advisories
  [ "$status" -eq 2 ]
  [ "$(jq -r .status <<<"$output")" = error ]
}

@test "advisories: giorni e mesi non dipendono dalla lingua del sistema" {
  make_feed
  export LC_ALL=it_IT.UTF-8 LANG=it_IT.UTF-8
  run --separate-stderr "$DEVBAR" check advisories
  [ "$(jq -r .count <<<"$output")" = 2 ]
}

@test "advisories: --force salta la cache" {
  make_feed
  run --separate-stderr "$DEVBAR" check advisories
  run --separate-stderr "$DEVBAR" check advisories --force
  [ "$(grep -c . "$BATS_TEST_TMPDIR/curl.calls")" = 2 ]
}

@test "advisories: output valido per lo schema" {
  make_feed
  run --separate-stderr "$DEVBAR" check advisories
  schema_ok advisories "$output"
}
