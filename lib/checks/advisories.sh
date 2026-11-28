#!/usr/bin/env bash
# devbar: check advisories (advisory di sicurezza recenti dal feed di smzstudio.it).

DEVBAR_ADVISORIES_URL="https://smzstudio.it/advisories/index.xml"
# Il sito si rigenera ogni 6 ore: inutile scaricare più spesso.
DEVBAR_ADVISORIES_CACHE_MINUTES=360

# advisories_days: finestra in giorni da advisoriesDays (intero 1..90), altrimenti 7.
advisories_days() {
  local d
  d="$(config_get .advisoriesDays)"
  if [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -ge 1 ] && [ "$d" -le 90 ]; then
    echo "$d"
  else
    echo 7
  fi
}

# advisories_fetch: scarica il feed e stampa le voci come JSON (tutte, non filtrate).
# Il feed passa da xsltproc (campi separati da tab, una voce per riga), poi jq.
advisories_fetch() {
  local xml sheet tsv
  xml="$(mktemp "${TMPDIR:-/tmp}/devbar-adv.XXXXXX")"
  sheet="$(mktemp "${TMPDIR:-/tmp}/devbar-adv.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$xml' '$sheet'" RETURN
  curl -fsS --max-time 30 "$DEVBAR_ADVISORIES_URL" >"$xml" 2>/dev/null || return 1
  cat >"$sheet" <<'XSL'
<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="text" encoding="UTF-8"/>
  <xsl:template match="/">
    <xsl:for-each select="/rss/channel/item">
      <xsl:value-of select="normalize-space(title)"/><xsl:text>&#9;</xsl:text>
      <xsl:value-of select="normalize-space(link)"/><xsl:text>&#9;</xsl:text>
      <xsl:value-of select="normalize-space(guid)"/><xsl:text>&#9;</xsl:text>
      <xsl:value-of select="normalize-space(pubDate)"/><xsl:text>&#9;</xsl:text>
      <xsl:for-each select="category"><xsl:value-of select="normalize-space(.)"/><xsl:text>|</xsl:text></xsl:for-each>
      <xsl:text>&#9;</xsl:text>
      <xsl:value-of select="normalize-space(description)"/>
      <xsl:text>&#10;</xsl:text>
    </xsl:for-each>
  </xsl:template>
</xsl:stylesheet>
XSL
  tsv="$(xsltproc "$sheet" "$xml" 2>/dev/null)" || return 1
  # un feed senza nessuna voce non è un feed valido: meglio un errore che "tutto a posto"
  [ -n "$tsv" ] || return 1
  printf '%s\n' "$tsv" | jq -R -s -c '
    def sev: ["CRITICAL","HIGH","MEDIUM","LOW","UNKNOWN"];
    # Data RFC 822 senza strptime: i nomi di giorno e mese seguono la lingua del Mac.
    def parse_date:
      first(
        ( (capture("^(?:[A-Za-z]{3}, )?(?<d>[0-9]{1,2}) (?<m>[A-Za-z]{3}) (?<y>[0-9]{4}) (?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})(?: (?<z>[+-][0-9]{4}))?")) as $c
          | (["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"] | index($c.m)) as $i
          | select($i != null)
          | ($c.z // "+0000") as $z
          | ((($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60) * (if $z[0:1] == "-" then -1 else 1 end)) as $off
          | ("\($c.y)-\(($i + 1) | tostring | if length < 2 then "0" + . else . end)-\($c.d | if length < 2 then "0" + . else . end)T\($c.t)Z" | fromdateiso8601) - $off ),
        null);
    [ split("\n")[] | select(length > 0) | split("\t")
      | { title: .[0], url: .[1], guid: .[2], date: (.[3] | try parse_date catch null), cats: (.[4] | split("|") | map(select(length > 0))),
          text: (.[5] | gsub("<[^>]*>"; " ") | gsub("\\s+"; " ")) }
      | select(.date != null)
      | . as $r
      | ( .title
          | if test("^\\[ALERT[^\\]]*\\] ") then {severity: "ALERT", score: null, package: "", title: sub("^\\[ALERT[^\\]]*\\] "; "")}
            elif test("^\\[[A-Za-z]+( [0-9.]+)?\\] [^ ]+ — ") then
              capture("^\\[(?<s>[A-Za-z]+)(?: (?<n>[0-9.]+))?\\] (?<p>[^ ]+) — (?<t>.*)$")
              | {severity: ((.s | ascii_upcase) as $u | if (sev | index($u)) then $u else "UNKNOWN" end),
                 score: (if .n then (.n | tonumber) else null end), package: .p, title: .t}
            else {severity: "UNKNOWN", score: null, package: "", title: $r.title} end ) as $t
      | { id: ((($r.text | capture("(?<c>CVE-[0-9]+-[0-9]+)").c) // ($r.text | capture("(?<g>GHSA(-[a-z0-9]{4}){3})").g)) // $r.guid),
          severity: $t.severity, score: $t.score, package: $t.package,
          ecosystem: (($r.cats | map(select(ascii_downcase | IN("critical","high","medium","low","unknown") | not)) | .[0]) // ""),
          title: $t.title, published: ($r.date | todate), url: $r.url,
          source: (($r.text | capture("fonte: (?<s>.*)$").s) // "" | sub("\\s+$"; "")) } ]'
}

# check_advisories: advisory degli ultimi advisoriesDays giorni. Cache 6 ore, --force la salta.
check_advisories() {
  local force="${1:-}" days all items count cutoff
  require_tool curl
  require_tool xsltproc
  days="$(advisories_days)"
  if [ "$force" = "--force" ] || ! cache_fresh advisories "$DEVBAR_ADVISORIES_CACHE_MINUTES"; then
    if all="$(advisories_fetch)" && [ -n "$all" ]; then
      printf '%s\n' "$all" | cache_write advisories
    elif [ -f "$(devbar_cache_dir)/advisories.json" ]; then
      echo "devbar: feed delle advisory non raggiungibile, uso la cache" >&2
    else
      emit error 0 "feed delle advisory non raggiungibile"
    fi
  fi
  cutoff="$(($(date -u +%s) - days * 86400))"
  items="$(cache_read advisories | jq -c --argjson cut "$cutoff" '
    [ .[] | select((.published | fromdateiso8601) >= $cut) ] | sort_by(.published) | reverse')" ||
    emit error 0 "cache delle advisory non valida"
  count="$(jq '[.[] | select(.severity | IN("CRITICAL","HIGH","ALERT"))] | length' <<<"$items")"
  local per="negli ultimi $days giorni"
  [ "$days" -eq 1 ] && per="nell'ultimo giorno"
  if [ "$count" -eq 0 ]; then
    emit ok 0 "Nessuna advisory grave $per" "$items"
  fi
  if [ "$count" -eq 1 ]; then
    emit action 1 "1 advisory grave $per" "$items"
  fi
  emit action "$count" "$count advisory gravi $per" "$items"
}
