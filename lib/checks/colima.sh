#!/usr/bin/env bash
# devbar: check colima (profili e container). Informativo: rc 1 se installato.

# check_colima: profili da `colima list --json` (una riga JSON per profilo);
# container da `docker stats` solo se un profilo è Running.
check_colima() {
  require_tool colima
  local raw profiles running containers stats
  raw="$(colima list --json 2>/dev/null || true)"
  # nessun output = nessun profilo; altrimenti ogni riga deve essere un profilo con name e status
  profiles='[]'
  if [ -n "$raw" ]; then
    profiles="$(printf '%s\n' "$raw" | jq -c -s '
      if all(.[]; type == "object" and (.name | type) == "string" and (.status | type) == "string")
      then map({name, status, cpus: (.cpus // 0), memoryBytes: (.memory // 0), diskBytes: (.disk // 0)})
      else empty end' 2>/dev/null)" || profiles=""
    [ -n "$profiles" ] || format_error colima colima version
  fi
  running="$(jq '[.[] | select(.status == "Running")] | length' <<<"$profiles")"
  containers='[]'
  if [ "$running" -gt 0 ]; then
    if command -v docker >/dev/null 2>&1 &&
      stats="$(docker stats --no-stream --format json 2>/dev/null)"; then
      containers="$(printf '%s\n' "$stats" | jq -c -s '
        map(select(type == "object")
          | {id: (.ID // .Container // ""), name: (.Name // ""), cpu: (.CPUPerc // ""),
             mem: ((.MemUsage // "") | split(" / ")[0])})' 2>/dev/null)" || containers='[]'
      [ -n "$containers" ] || containers='[]'
    else
      echo "devbar: docker non raggiungibile (container non elencati)" >&2
    fi
  fi
  local n summary extra
  n="$(jq 'length' <<<"$containers")"
  if [ "$running" -gt 0 ]; then
    summary="$running profili colima attivi, $n container"
    [ "$running" -eq 1 ] && summary="1 profilo colima attivo, $n container"
  else
    summary="Colima spento"
  fi
  extra="$(jq -nc --argjson p "$profiles" --argjson c "$containers" '{profiles:$p,containers:$c}')"
  emit ok "$running" "$summary" "[]" "$extra"
}
