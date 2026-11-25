#!/usr/bin/env bash
# devbar: scansione repo (repos) e audit dipendenze (npm-audit, composer-audit).

# scan_repo_dirs: stampa le cartelle repo (una per riga) dentro repoRoots.
# Repo = cartella con package-lock.json o composer.lock, fino a scanDepth
# livelli sotto la root; salta node_modules, vendor, .git.
scan_repo_dirs() {
  local roots depth root
  roots="$(config_get .repoRoots)"
  depth="$(config_get .scanDepth)"
  case "$depth" in '' | *[!0-9]*) depth=4 ;; esac
  jq -r '.[]' <<<"$roots" | while IFS= read -r root; do
    [ -n "$root" ] || continue
    root="${root/#\~/$HOME}"
    if [ ! -d "$root" ] || [ ! -r "$root" ]; then
      echo "devbar: cartella repo non accessibile, saltata: $root" >&2
      continue
    fi
    find "$root" -maxdepth "$((depth + 1))" \
      \( -name node_modules -o -name vendor -o -name .git \) -prune -o \
      \( -name package-lock.json -o -name composer.lock \) -type f -print 2>/dev/null |
      while IFS= read -r f; do dirname "$f"; done
  done | sort -u
}

# list_repos: stampa l'array JSON dei repo trovati.
list_repos() {
  local d
  scan_repo_dirs | while IFS= read -r d; do
    [ -n "$d" ] || continue
    jq -n --arg p "$d" \
      --argjson n "$([ -f "$d/package-lock.json" ] && echo true || echo false)" \
      --argjson c "$([ -f "$d/composer.lock" ] && echo true || echo false)" \
      --argjson t "$([ -d "$d/.tokensave" ] && echo true || echo false)" \
      '{path:$p,name:($p|split("/")|last),npm:$n,composer:$c,tokensave:$t}'
  done | jq -s '.'
}

cmd_repos() { list_repos; }

# _audit_repo_counts <npm|composer> <dir>: stampa {critical,high,moderate,low}
# dell'audit nel repo; niente in output se l'audit non dà JSON valido.
_audit_repo_counts() {
  local kind="$1" d="$2" raw json
  if [ "$kind" = npm ]; then
    raw="$(cd "$d" && npm audit --json 2>/dev/null || true)"
  else
    raw="$(cd "$d" && composer audit --format=json --locked 2>/dev/null || true)"
  fi
  json="$(printf '%s\n' "$raw" | extract_json)"
  [ -n "$json" ] || return 0
  # errore dichiarato dallo strumento (es. rete assente): il messaggio va nel file di errore
  # (_AUDIT_ERRFILE, impostato da audit_repos), il risultato resta vuoto.
  if [ -n "${_AUDIT_ERRFILE:-}" ]; then
    jq -r 'select(type == "object" and .error != null) | .error
      | if type == "object" then (.summary // .message // .code // "errore sconosciuto") else tostring end
      | gsub("\n"; " ") | .[0:200]' <<<"$json" 2>/dev/null | head -n 1 >>"$_AUDIT_ERRFILE" || true
  fi
  if [ "$kind" = npm ]; then
    jq -c '.metadata.vulnerabilities
      | select(type == "object" and all(.critical, .high, .moderate, .low; type == "number"))
      | {critical, high, moderate, low}' <<<"$json" 2>/dev/null || true
  else
    jq -c '
      .advisories | select(type == "object" or type == "array")
      | [ if type == "array" then empty else to_entries[].value
          | if type == "array" then .[] else . end end
          | (.severity // "" | ascii_downcase) ] as $s
      | {critical:([$s[]|select(.=="critical")]|length),
         high:([$s[]|select(.=="high")]|length),
         moderate:([$s[]|select(.=="medium" or .=="moderate")]|length),
         low:([$s[]|select(.=="low")]|length)}' <<<"$json" 2>/dev/null || true
  fi
}

# audit_repos <npm|composer> <force>: logica comune dei due check.
# Cache: una per repo (<kind>-audit-repo-<hash del percorso>, 24h), così un giro
# interrotto dal timeout non perde i repo già fatti; e una aggregata per
# configurazione (<kind>-audit-cfg-<hash di repoRoots+scanDepth>): cambiare le
# cartelle o la profondità la invalida, le cache per repo restano valide.
# --force rifà l'audit di ogni repo (e riscrive le cache per repo).
audit_repos() {
  local kind="$1" force="$2" cache repos items count vulns errs counts d rcache
  require_tool "$kind"
  _AUDIT_ERRFILE="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$_AUDIT_ERRFILE'" EXIT
  if [ "$(config_get '.repoRoots | length')" -eq 0 ]; then
    emit unconfigured 0 "nessuna cartella repo configurata"
  fi
  cache="$kind-audit-cfg-$(devbar_hash "$(config_get .repoRoots)|$(config_get .scanDepth)")"
  if [ "$force" != "--force" ] && cache_fresh "$cache" "$(vuln_cache_minutes)"; then
    items="$(cache_read "$cache")"
  else
    repos="$(list_repos | jq -r --arg k "$kind" '.[] | select(.[$k]) | .path')"
    items="[]"
    errs=0
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      rcache="$kind-audit-repo-$(devbar_hash "$d")"
      if [ "$force" != "--force" ] && cache_fresh "$rcache" "$(vuln_cache_minutes)"; then
        counts="$(cache_read "$rcache")"
      else
        counts="$(_audit_repo_counts "$kind" "$d")"
        # solo i risultati validi vanno in cache: un errore si riprova al prossimo giro
        [ -z "$counts" ] || printf '%s\n' "$counts" | cache_write "$rcache"
      fi
      if [ -z "$counts" ]; then
        errs=$((errs + 1))
        items="$(jq -c --arg r "$d" --arg e "output di $kind audit non valido" '. + [{repo:$r,error:$e}]' <<<"$items")"
      elif [ "$(jq '[.critical,.high,.moderate,.low] | add' <<<"$counts")" -gt 0 ]; then
        items="$(jq -c --arg r "$d" --argjson c "$counts" '. + [{repo:$r} + $c]' <<<"$items")"
      fi
    done <<<"$repos"
    # con errori non si salva in cache: il prossimo giro riprova
    if [ "$errs" -eq 0 ]; then printf '%s\n' "$items" | cache_write "$cache"; fi
  fi
  count="$(jq 'length' <<<"$items")"
  vulns="$(jq '[.[] | select(has("error") | not)] | length' <<<"$items")"
  errs="$(jq '[.[] | select(has("error"))] | length' <<<"$items")"
  if [ "$count" -eq 0 ]; then
    emit ok 0 "Nessuna vulnerabilità $kind" "[]"
  elif [ "$vulns" -eq 0 ]; then
    local vflag=--version toolerr
    [ "$kind" != npm ] || vflag=-v
    toolerr="$(grep -m1 . "$_AUDIT_ERRFILE" 2>/dev/null || true)"
    if [ -n "$toolerr" ]; then
      emit error "$count" "$kind audit non riuscito: $toolerr" "$items"
    fi
    emit error "$count" "audit $kind fallito in $errs repo: formato di $kind non riconosciuto (versione $(tool_version "$kind" "$vflag"))" "$items"
  fi
  emit action "$count" "$vulns repo con vulnerabilità $kind ($errs con errori)" "$items"
}

check_npm_audit() { audit_repos npm "${1:-}"; }
check_composer_audit() { audit_repos composer "${1:-}"; }
