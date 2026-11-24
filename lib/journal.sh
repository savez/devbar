#!/usr/bin/env bash
# shellcheck disable=SC2016 # i filtri jq usano variabili jq ($i, $p, …), non di shell
# devbar: registro delle modifiche ai file di altri programmi e `devbar undo`.
#
# Ogni `devbar run …` che scrive in file non di devbar crea UNA voce in
# ~/.local/state/devbar/journal/<timestamp>-<id>/ (id fisso per processo: DEVBAR_JOURNAL_ID):
#   meta.json  {id, time, command, files:[{path, kind, existed, sha256Before, sha256After,
#              backup, linkTarget}], undoneAt?}
#   files/     copia di ogni percorso com'era prima della prima scrittura (file: cp -p;
#              cartella: tar; link: solo il target in meta).
# Tutto lo stato è su disco: le scritture avvengono anche in sottoshell (pipeline).
# journal_before si chiama prima di scrivere (devbar_write_file, mv/ln/cp/rm, strumenti
# esterni); journal_settle (trap EXIT di `run`) aggiorna sha256After e toglie i percorsi
# rimasti uguali; una voce senza cambiamenti sparisce. Non registrati: config e cache di
# devbar, il registro stesso. Tiene le ultime $JOURNAL_KEEP voci.
#
# undo: senza --yes il piano; con --yes ripristina. Un file il cui hash attuale non è né
# sha256After né sha256Before è stato cambiato da altri: senza --force non si scrive nulla.
# I backup non vengono mai cancellati da undo (solo dalla rotazione delle voci).

JOURNAL_KEEP=50

journal_root() { printf '%s' "${DEVBAR_STATE_DIR:-$HOME/.local/state/devbar}/journal"; }

# journal_begin <comando...>: id e cartella della voce per questo processo (creata solo alla
# prima scrittura). I figli ereditano la stessa voce.
journal_begin() {
  if [ -z "${DEVBAR_JOURNAL_ID:-}" ]; then
    DEVBAR_JOURNAL_ID="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  fi
  if [ -z "${DEVBAR_JOURNAL_ENTRY:-}" ]; then
    DEVBAR_JOURNAL_ENTRY="$(journal_root)/$(date -u +%Y%m%dT%H%M%SZ)-$DEVBAR_JOURNAL_ID"
    DEVBAR_JOURNAL_CMD="$*"
  fi
  export DEVBAR_JOURNAL_ID DEVBAR_JOURNAL_ENTRY DEVBAR_JOURNAL_CMD
}

_journal_abs() {
  case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac
}

# _journal_skip <percorso-assoluto>: rc 0 se è un file di devbar (non registrato).
_journal_skip() {
  local p="$1" d
  [ "$p" = "$(devbar_config_path)" ] && return 0
  for d in "$(devbar_cache_dir)" "$HOME/.cache/devbar" "${DEVBAR_STATE_DIR:-$HOME/.local/state/devbar}"; do
    case "$p" in "$d" | "$d"/*) return 0 ;; esac
  done
  return 1
}

# _journal_kind <percorso>: link | dir | file | none.
_journal_kind() {
  if [ -L "$1" ]; then echo link
  elif [ -d "$1" ]; then echo dir
  elif [ -e "$1" ]; then echo file
  else echo none; fi
}

# sha256sum (macOS recenti, avvio rapido) se c'è, altrimenti shasum (perl).
if command -v sha256sum >/dev/null 2>&1; then _JOURNAL_SHA=(sha256sum); else _JOURNAL_SHA=(shasum -a 256); fi
_journal_sha() { "${_JOURNAL_SHA[@]}" | cut -c1-64; }

# _journal_hash <percorso>: sha256 del contenuto; cartelle: dell'elenco (tipo, nome, hash);
# link: del target. Vuoto se il percorso non esiste.
_journal_hash() {
  local p="$1"
  case "$(_journal_kind "$p")" in
    link) printf 'link:%s' "$(readlink "$p")" | _journal_sha ;;
    file) _journal_sha <"$p" ;;
    dir)
      # cartelle e link per nome, file con il loro hash (un solo processo di hash per tutti)
      (cd "$p" && {
        find . -type d | sed 's/^/D /'
        find . -type l | while IFS= read -r f; do printf 'L %s %s\n' "$f" "$(readlink "$f")"; done
        find . -type f -exec "${_JOURNAL_SHA[@]}" {} + | awk '{ h=$1; sub(/^[0-9a-f]+  /, ""); print "F " $0 " " h }'
      } | LC_ALL=C sort) | _journal_sha
      ;;
    none) printf '' ;;
  esac
}

# _journal_meta_set <meta> <filtro jq> [args...]: riscrive meta.json in modo atomico.
_journal_meta_set() {
  local meta="$1" filter="$2" tmp
  shift 2
  tmp="$(mktemp "$(dirname "$meta")/.meta.XXXXXX")" || return 1
  if ! jq "$filter" "$@" "$meta" >"$tmp"; then rm -f "$tmp"; return 1; fi
  mv "$tmp" "$meta"
}

# _journal_prune: tiene le ultime JOURNAL_KEEP voci (ordine per nome = per data), mai la corrente.
_journal_prune() {
  local root n d
  root="$(journal_root)"
  n="$(find "$root" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  [ "$n" -gt "$JOURNAL_KEEP" ] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | head -n "$((n - JOURNAL_KEEP))" |
    while IFS= read -r d; do
      [ "$d" = "$DEVBAR_JOURNAL_ENTRY" ] && continue
      rm -rf "${d:?}"
    done
}

# _journal_open: crea la voce corrente se manca.
_journal_open() {
  local e="$DEVBAR_JOURNAL_ENTRY" root
  [ -f "$e/meta.json" ] && return 0
  root="$(journal_root)"
  mkdir -p "$root" && chmod 700 "$root" "$(dirname "$root")" || return 1
  mkdir -p "$e/files" || return 1
  jq -n --arg id "$DEVBAR_JOURNAL_ID" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg c "${DEVBAR_JOURNAL_CMD:-}" '{id:$id,time:$t,command:$c,files:[]}' >"$e/meta.json" || return 1
  _journal_prune
}

# journal_before <percorso>...: registra lo stato attuale di ogni percorso (una volta per voce).
# Fuori da `devbar run` (nessuna voce) non fa nulla. Backup fallito: rc 1, non scrivere.
journal_before() {
  [ -n "${DEVBAR_JOURNAL_ENTRY:-}" ] || return 0
  local p e meta kind sha backup="" target="" rec
  e="$DEVBAR_JOURNAL_ENTRY"
  meta="$e/meta.json"
  for p in "$@"; do
    p="$(_journal_abs "$p")"
    _journal_skip "$p" && continue
    _journal_open || return 1
    jq -e --arg p "$p" 'any(.files[]; .path == $p)' "$meta" >/dev/null && continue
    kind="$(_journal_kind "$p")"
    backup="" target=""
    case "$kind" in
      file)
        backup="$(mktemp "$e/files/b.XXXXXX")" || return 1
        cp -p "$p" "$backup" || { echo "devbar: backup fallito: $p" >&2; return 1; }
        ;;
      dir)
        backup="$(mktemp "$e/files/b.XXXXXX")" || return 1
        tar -cf "$backup" -C "$(dirname "$p")" "$(basename "$p")" 2>/dev/null ||
          { echo "devbar: backup fallito: $p" >&2; return 1; }
        ;;
      link) target="$(readlink "$p")" ;;
    esac
    sha="$(_journal_hash "$p")" || return 1
    [ -z "$backup" ] || backup="files/$(basename "$backup")"
    rec="$(jq -nc --arg p "$p" --arg k "$kind" --arg s "$sha" --arg b "$backup" --arg t "$target" \
      '{path:$p, kind:$k, existed:($k != "none"), sha256Before:(if $s == "" then null else $s end),
        sha256After:(if $s == "" then null else $s end), backup:(if $b == "" then null else $b end),
        linkTarget:(if $k == "link" then $t else null end)}')"
    _journal_meta_set "$meta" '.files += [$r]' --argjson r "$rec" || return 1
  done
}

# journal_settle: sha256After = stato attuale; percorsi invariati tolti (col loro backup,
# identico al file attuale); voce vuota rimossa. Chiamato all'uscita di `devbar run`.
journal_settle() {
  [ -n "${DEVBAR_JOURNAL_ENTRY:-}" ] || return 0
  local e="$DEVBAR_JOURNAL_ENTRY" meta i n p sha before b kind
  meta="$e/meta.json"
  [ -f "$meta" ] || return 0
  n="$(jq '.files | length' "$meta")"
  i=$((n - 1))
  while [ "$i" -ge 0 ]; do
    p="$(jq -r --argjson i "$i" '.files[$i].path' "$meta")"
    before="$(jq -r --argjson i "$i" '.files[$i].sha256Before // ""' "$meta")"
    sha="$(_journal_hash "$p")"
    if [ "$sha" = "$before" ]; then
      b="$(jq -r --argjson i "$i" '.files[$i].backup // ""' "$meta")"
      _journal_meta_set "$meta" 'del(.files[$i])' --argjson i "$i" || return 1
      [ -z "$b" ] || rm -f "${e:?}/$b"
    else
      kind="$(_journal_kind "$p")"
        _journal_meta_set "$meta" '.files[$i].sha256After = (if $s == "" then null else $s end)
        | if .files[$i].existed then . else .files[$i].kind = $k end' \
        --argjson i "$i" --arg s "$sha" --arg k "$kind" || return 1
    fi
    i=$((i - 1))
  done
  if [ "$(jq '.files | length' "$meta")" -eq 0 ]; then rm -rf "${e:?}"; fi
}

# --- lettura e undo ---

# _journal_files_state <meta>: files con `changed` e `action` (restore|remove|none) attuali.
_journal_files_state() {
  local meta="$1" p hashes=()
  # un hash per file (ordine di .files); jq una volta per leggere e una per combinare
  while IFS= read -r p; do
    hashes+=("$(_journal_hash "$p")")
  done < <(jq -r '.files[].path' "$meta")
  jq -c '[.files as $f | range(0; $f | length) as $i | $ARGS.positional[$i] as $cur | $f[$i]
    | (.sha256Before // "") as $b | (.sha256After // "") as $a
    | . + (if $cur == $b then {action:"none", changed:false}
           else {action:(if .existed then "restore" else "remove" end), changed:($cur != $a)} end)]' \
    "$meta" --args ${hashes[@]+"${hashes[@]}"}
}

# _journal_entries: cartelle delle voci, dalla più recente.
_journal_entries() {
  local root
  root="$(journal_root)"
  [ -d "$root" ] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort -r
}

# cmd_journal [--limit N]: {entries:[{id,time,command,undone,files:[{path,kind,existed,
# sha256Before,sha256After,changed}]}]}, dalla più recente; con --limit solo le prime N
# (l'hash attuale si calcola solo per quelle). Voci illeggibili saltate.
cmd_journal() {
  local d files limit="" n=0
  if [ "${1:-}" = --limit ]; then
    case "${2:-}" in '' | *[!0-9]*) _journal_error "uso: devbar journal [--limit N]"; return 2 ;; esac
    limit="$2"
  fi
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -z "$limit" ] || [ "$n" -lt "$limit" ] || break
    jq -e 'type == "object" and (.files | type) == "array"' "$d/meta.json" >/dev/null 2>&1 || continue
    files="$(_journal_files_state "$d/meta.json")"
    jq -c --argjson f "$files" '{id, time, command, undone:(.undoneAt != null),
      files:[$f[] | {path, kind, existed, sha256Before, sha256After, changed}]}' "$d/meta.json"
    n=$((n + 1))
  done < <(_journal_entries) | jq -s '{entries:.}'
}

# _journal_find <id>: cartella della voce; senza id la più recente non annullata.
_journal_find() {
  local id="$1" d
  while IFS= read -r d; do
    [ -n "$d" ] && [ -f "$d/meta.json" ] || continue
    if [ -n "$id" ]; then
      [ "$(jq -r .id "$d/meta.json")" = "$id" ] && { printf '%s' "$d"; return 0; }
    elif [ "$(jq -r '.undoneAt // ""' "$d/meta.json")" = "" ]; then
      printf '%s' "$d"
      return 0
    fi
  done < <(_journal_entries)
  return 1
}

# _journal_restore <voce> <record-json>: rimette il percorso com'era (o lo toglie se creato).
# Il contenuto nuovo si prepara accanto al target; quello attuale si sposta da parte e torna
# al suo posto se il passo finale fallisce. Il backup nella voce non viene toccato.
_journal_restore() {
  local e="$1" r="$2" p kind existed backup target parent base tmp="" aside="" new=""
  p="$(jq -r .path <<<"$r")"
  kind="$(jq -r .kind <<<"$r")"
  existed="$(jq -r .existed <<<"$r")"
  backup="$(jq -r '.backup // ""' <<<"$r")"
  target="$(jq -r '.linkTarget // ""' <<<"$r")"
  case "$p" in / | "$HOME" | "$HOME/") echo "devbar: percorso rifiutato: $p" >&2; return 1 ;; esac
  parent="$(dirname "$p")"
  base="$(basename "$p")"
  if [ "$existed" = true ]; then
    mkdir -p "$parent" || return 1
    case "$kind" in
      file)
        tmp="$(mktemp "$parent/.devbar-undo.XXXXXX")" || return 1
        cp -p "$e/$backup" "$tmp" || { rm -f "$tmp"; return 1; }
        new="$tmp"
        ;;
      dir)
        tmp="$(mktemp -d "$parent/.devbar-undo.XXXXXX")" || return 1
        tar -xpf "$e/$backup" -C "$tmp" || { rm -rf "${tmp:?}"; return 1; }
        new="$tmp/$base"
        ;;
    esac
  fi
  if [ -e "$p" ] || [ -L "$p" ]; then
    aside="$parent/.devbar-undo-old.$$.$RANDOM"
    mv "$p" "$aside" || { [ -z "$tmp" ] || rm -rf "${tmp:?}"; return 1; }
  fi
  if [ "$existed" = true ]; then
    if { [ "$kind" = link ] && ln -s "$target" "$p"; } || { [ "$kind" != link ] && mv "$new" "$p"; }; then
      :
    else
      [ -z "$aside" ] || mv "$aside" "$p"
      [ -z "$tmp" ] || rm -rf "${tmp:?}"
      return 1
    fi
    [ "$kind" != dir ] || rmdir "$tmp" 2>/dev/null || true
  fi
  [ -z "$aside" ] || rm -rf "${aside:?}"
}

# cmd_undo [<id>] [--yes] [--force]
cmd_undo() {
  local id="" yes=false force=false a d meta files lines needs n i r act failed=""
  unset DEVBAR_JOURNAL_ID DEVBAR_JOURNAL_ENTRY
  for a in "$@"; do
    case "$a" in
      --yes) yes=true ;;
      --force) force=true ;;
      *) [ -z "$id" ] || { _journal_error "uso: devbar undo [<id>] [--yes] [--force]"; return 2; }; id="$a" ;;
    esac
  done
  case "$id" in *[!A-Za-z0-9_-]* | -*) _journal_error "id non valido: $id"; return 2 ;; esac
  d="$(_journal_find "$id")" || {
    if [ -n "$id" ]; then _journal_error "modifica non trovata: $id"; else _journal_error "nessuna modifica da annullare"; fi
    return 2
  }
  meta="$d/meta.json"
  id="$(jq -r .id "$meta")"
  if [ "$(jq -r '.undoneAt // ""' "$meta")" != "" ]; then
    _journal_error "modifica già annullata: $id"
    return 2
  fi
  files="$(_journal_files_state "$meta")"
  needs="$(jq '[.[] | select(.changed)] | length > 0' <<<"$files")"
  lines="$(jq -c --arg h "$HOME" '[reverse[] | (.path | if startswith($h + "/") then "~" + .[($h | length):] else . end) as $t
    | (if .action == "restore" then "ripristina " + $t
       elif .action == "remove" then "rimuove " + $t + " (creato da devbar)"
       else "già com'"'"'era: " + $t end)
      + (if .changed then " — ATTENZIONE: cambiato da un altro programma dopo devbar, quelle modifiche andrebbero perse (serve --force)" else "" end)]' <<<"$files")"
  if [ "$yes" = false ]; then
    jq -n --arg id "$id" --argjson c "$lines" --argjson n "$needs" --argjson f "$files" \
      --arg t "$(jq -r .time "$meta")" --arg cmd "$(jq -r .command "$meta")" \
      '{plan:true, id:$id, time:$t, command:$cmd, needsForce:$n, commands:$c,
        files:[$f[] | {path, action, changed}]}'
    return 0
  fi
  if [ "$needs" = true ] && [ "$force" = false ]; then
    _journal_error "file cambiati da un altro programma dopo devbar: $(jq -r '[.[] | select(.changed) | .path] | join(", ")' <<<"$files") (nessun file toccato; usa --force per sovrascriverli)"
    return 2
  fi
  # Ogni backup necessario deve esistere prima di toccare qualsiasi file.
  n="$(jq length <<<"$files")"
  i=0
  while [ "$i" -lt "$n" ]; do
    r="$(jq -c --argjson i "$i" '.[$i]' <<<"$files")"
    if [ "$(jq -r '.action == "restore" and .kind != "link"' <<<"$r")" = true ] &&
      [ ! -f "$d/$(jq -r '.backup // ""' <<<"$r")" ]; then
      _journal_error "backup mancante per $(jq -r .path <<<"$r"): nessun file toccato"
      return 2
    fi
    i=$((i + 1))
  done
  i=$((n - 1))
  while [ "$i" -ge 0 ]; do
    r="$(jq -c --argjson i "$i" '.[$i]' <<<"$files")"
    act="$(jq -r .action <<<"$r")"
    if [ "$act" != none ] && ! _journal_restore "$d" "$r" </dev/null; then
      failed="$(jq -r .path <<<"$r")"
      break
    fi
    i=$((i - 1))
  done
  if [ -n "$failed" ]; then
    _journal_error "ripristino fallito: $failed (backup conservati in $d; riprova dopo aver risolto)"
    return 2
  fi
  _journal_meta_set "$meta" '.undoneAt = $t' --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || {
    _journal_error "file ripristinati, ma registro non aggiornato: $meta"
    return 2
  }
  jq -n --arg id "$id" --argjson c "$lines" '{applied:true, id:$id, commands:$c}'
}

_journal_error() { jq -nc --arg e "$1" '{status:"error",error:$e}'; }
