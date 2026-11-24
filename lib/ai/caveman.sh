#!/usr/bin/env bash
# devbar: AI setup per caveman (vedi interfaccia in lib/ai/ai.sh).
#
# Portato da github.com/sparkfabrik/sparkdock (sjust/scripts/caveman/setup.sh), GPLv3
# (ensure_caveman_repo, caveman_installer_path, write_default_config, setup_claude,
# setup_opencode, setup_copilot, inject_with_markers). Non portati: uninstall e
# normalize_claude_settings (claude-fix-settings.sh).
#
# Dipendenze: git (clone/aggiornamento del repo), node (installer ufficiale per
# claude e opencode; copilot non lo richiede ma il tool risulta installato solo
# con entrambi). Il clone è un'azione di rete: avviene solo sotto --yes.
# Cache: ~/.cache/devbar/caveman. Scritture file via devbar_write_file (Ruling E).

_CAVEMAN_REPO_URL="https://github.com/JuliusBrussee/caveman.git"
_CAVEMAN_MARKER_BEGIN="<!-- BEGIN CAVEMAN MANAGED BLOCK -->"
_CAVEMAN_MARKER_END="<!-- END CAVEMAN MANAGED BLOCK -->"
_CAVEMAN_DEFAULT_MODE="full"

_caveman_cache() { printf '%s' "$HOME/.cache/devbar/caveman"; }
_caveman_config() { printf '%s' "$HOME/.config/caveman/config.json"; }
_caveman_skills_dir() { printf '%s' "$HOME/.agents/skills"; }
_caveman_copilot_file() { printf '%s' "$HOME/.copilot/copilot-instructions.md"; }
_caveman_claude_dir() { printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

ai_caveman_supports() {
  case "$1" in claude | opencode | copilot) return 0 ;; esac
  return 1
}

ai_caveman_installed() {
  command -v git >/dev/null 2>&1 && command -v node >/dev/null 2>&1
}

# claude: plugin nella cache dei plugin; opencode: plugin caveman presente
# (outdated se diverso dalla patch); copilot: blocco gestito (outdated se
# diverso dalla regola nella cache, quando c'è).
ai_caveman_state() {
  local rule f cur patch
  case "$1" in
    claude)
      if [ -d "$(_caveman_claude_dir)/plugins/cache/caveman" ]; then echo installed; else echo missing; fi
      ;;
    opencode)
      f="$HOME/.config/opencode/plugins/caveman/plugin.js"
      patch="$DEVBAR_ROOT/lib/ai/patches/caveman-opencode-plugin.js"
      if [ ! -f "$f" ]; then
        echo missing
      elif [ -f "$patch" ] && ! cmp -s "$patch" "$f"; then
        echo outdated
      else echo installed; fi
      ;;
    copilot)
      f="$(_caveman_copilot_file)"
      if [ -f "$f" ] && grep -q "$_CAVEMAN_MARKER_BEGIN" "$f" 2>/dev/null; then
        rule="$(_caveman_cache)/src/rules/caveman-activate.md"
        cur="$(awk -v b="$_CAVEMAN_MARKER_BEGIN" -v e="$_CAVEMAN_MARKER_END" '
          $0 ~ b { p=1; next } $0 ~ e { p=0 } p' "$f")"
        if [ -f "$rule" ] && [ "$cur" != "$(cat "$rule")" ]; then echo outdated; else echo installed; fi
      else
        echo missing
      fi
      ;;
    *) echo missing ;;
  esac
}

ai_caveman_install_cmds() {
  local h
  echo "git clone --depth=1 $_CAVEMAN_REPO_URL ~/.cache/devbar/caveman (o fetch + reset se già presente)"
  echo "scrivi ~/.config/caveman/config.json con defaultMode \"$_CAVEMAN_DEFAULT_MODE\" (solo se assente)"
  for h in "$@"; do
    case "$h" in
      claude) echo "node <cache>/<installer> --only claude --force --non-interactive --no-mcp-shrink" ;;
      opencode)
        echo "node <cache>/<installer> --only opencode --force --non-interactive --no-mcp-shrink"
        echo "rimuovi gli agent cavecrew-*.md incompatibili e applica la patch di plugin.js (caveman#386, #418)"
        ;;
      copilot)
        echo "copia la skill in ~/.agents/skills/caveman e linka ~/.copilot/skills, ~/.claude/skills"
        _caveman_replace_notes
        echo "scrivi il blocco CAVEMAN in ~/.copilot/copilot-instructions.md"
        ;;
    esac
  done
}

ai_caveman_install() {
  local h
  export PATH="$HOME/.local/bin:$PATH"
  for h in "$@"; do
    case "$h" in claude | opencode) command -v node >/dev/null 2>&1 || { echo "devbar: node richiesto per $h" >&2; return 1; } ;; esac
  done
  _caveman_ensure_repo || return 1
  _caveman_write_default_config || return 1
  for h in "$@"; do
    case "$h" in
      claude) _caveman_setup_native claude || return 1 ;;
      opencode) _caveman_setup_opencode || return 1 ;;
      copilot) _caveman_setup_copilot || return 1 ;;
    esac
  done
}

# --- Repository ---

_caveman_ensure_repo() {
  local cache compress_cmd
  cache="$(_caveman_cache)"
  echo "devbar: aggiorno il repo caveman..." >&2
  mkdir -p "$(dirname "$cache")" || return 1
  if [ ! -d "$cache/.git" ]; then
    git clone --depth=1 "$_CAVEMAN_REPO_URL" "$cache" </dev/null || return 1
  else
    git -C "$cache" fetch --depth=1 origin main </dev/null || return 1
    git -C "$cache" reset --hard origin/main </dev/null || return 1
  fi
  # Workaround upstream (2026-05-13): l'installer cita caveman-compress.md ma il
  # file manca dal repo; stub minimo perché l'install OpenCode non si fermi.
  compress_cmd="$cache/src/plugins/opencode/commands/caveman-compress.md"
  if [ -d "$cache/src/plugins/opencode" ] && [ ! -f "$compress_cmd" ]; then
    mkdir -p "$(dirname "$compress_cmd")" || return 1
    cat >"$compress_cmd" <<'STUB'
---
description: Compress a memory file into caveman format to save input tokens
---
Compress the following file into caveman format: $ARGUMENTS

Preserve all technical substance, code, URLs, and structure.
Save a human-readable backup as FILE.original.md before overwriting.
STUB
    echo "devbar: creato stub per file upstream mancante: caveman-compress.md" >&2
  fi
}

# Entry point dell'installer nativo: prima il bin `caveman-install` di
# package.json (upstream lo ha spostato più volte), poi i layout noti.
_caveman_installer_path() {
  local cache candidate
  cache="$(_caveman_cache)"
  candidate="$(node -e '
    const bin = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).bin;
    const path = typeof bin === "string" ? bin : (bin || {})["caveman-install"];
    if (path) { process.stdout.write(path); }
  ' "$cache/package.json" 2>/dev/null || true)"
  candidate="${candidate#./}"
  if [ -n "$candidate" ] && [ -f "$cache/$candidate" ]; then
    printf '%s\n' "$cache/$candidate"
    return 0
  fi
  for candidate in installer/install.js bin/install.js cli/install.js; do
    if [ -f "$cache/$candidate" ]; then
      printf '%s\n' "$cache/$candidate"
      return 0
    fi
  done
  return 1
}

# --- Config ---

# Non cambia defaultMode se il config esiste già.
_caveman_write_default_config() {
  local f
  f="$(_caveman_config)"
  if [ -e "$f" ]; then
    echo "devbar: config caveman già presente: $f (defaultMode invariato)" >&2
    return 0
  fi
  printf '{"defaultMode": "%s"}\n' "$_CAVEMAN_DEFAULT_MODE" | devbar_write_file "$f" || return 1
  echo "devbar: config caveman scritto: $f (mode: $_CAVEMAN_DEFAULT_MODE)" >&2
}

# --- Claude Code / OpenCode (installer nativo) ---

# _caveman_native_paths <claude|opencode>: file noti scritti dall'installer nativo (uno per riga).
# Limite: l'installer può toccare altro (cache dei plugin, comandi): non registrato.
_caveman_native_paths() {
  case "$1" in
    claude) printf '%s\n' "$(_caveman_claude_dir)/settings.json" ;;
    opencode) printf '%s\n' "$HOME/.config/opencode/opencode.json" "$HOME/.config/opencode/plugins/caveman" ;;
  esac
}

_caveman_setup_native() {
  local target="$1" installer
  if ! installer="$(_caveman_installer_path)"; then
    echo "devbar: installer caveman non trovato in $(_caveman_cache) (package.json bin, installer/install.js, bin/install.js, cli/install.js)" >&2
    return 1
  fi
  # l'installer scrive da sé: si registra prima lo stato dei file noti che tocca
  # shellcheck disable=SC2046 # un percorso per riga
  journal_before $(_caveman_native_paths "$target") </dev/null || return 1
  node "$installer" --only "$target" --force --non-interactive --no-mcp-shrink </dev/null || {
    echo "devbar: installer caveman fallito per $target" >&2
    return 1
  }
}

_caveman_setup_opencode() {
  local agents_dir="$HOME/.config/opencode/agents" f
  local patch="$DEVBAR_ROOT/lib/ai/patches/caveman-opencode-plugin.js"
  local dest="$HOME/.config/opencode/plugins/caveman/plugin.js"
  _caveman_setup_native opencode || return 1
  # Gli agent cavecrew-*.md usano un array `tools` che OpenCode rifiuta e blocca
  # l'avvio (https://github.com/JuliusBrussee/caveman/issues/386).
  for f in cavecrew-investigator.md cavecrew-builder.md cavecrew-reviewer.md; do
    if [ -f "$agents_dir/$f" ]; then
      journal_before "$agents_dir/$f" </dev/null || return 1
      rm -f "${agents_dir:?}/${f:?}"
      echo "devbar: rimosso agent incompatibile: $agents_dir/$f" >&2
    fi
  done
  # plugin.js upstream usa hook inesistenti (caveman#418): sostituito dalla patch.
  if [ -f "$patch" ]; then
    if [ -f "$dest" ]; then
      devbar_write_file "$dest" <"$patch" || return 1
      echo "devbar: applicata patch plugin.js OpenCode (caveman#418)" >&2
    else
      echo "devbar: patch plugin.js non applicabile: $dest non trovato" >&2
    fi
  fi
}

# --- Copilot ---

# _caveman_inject <file> <contenuto>: sostituisce/aggiunge il blocco gestito.
_caveman_inject() { inject_block "$1" "$_CAVEMAN_MARKER_BEGIN" "$_CAVEMAN_MARKER_END" "$2"; }

# _caveman_strip_block <file> <begin> <end>: toglie un blocco (no-op se assente o symlink).
_caveman_strip_block() {
  local file="$1" b="$2" e="$3"
  [ -f "$file" ] && [ ! -L "$file" ] || return 0
  grep -q "$b" "$file" 2>/dev/null || return 0
  awk -v b="$b" -v e="$e" '$0 ~ b { skip=1; next } $0 ~ e { skip=0; next } !skip' "$file" |
    devbar_write_file "$file" || return 1
  echo "devbar: rimosso blocco obsoleto da $file" >&2
}

# _caveman_tilde <path>: ~ al posto di $HOME, per i messaggi.
_caveman_tilde() {
  local t='~'
  printf '%s' "${1/#"$HOME"/$t}"
}

# _caveman_copilot_links: i link della skill (uno per riga).
_caveman_copilot_links() {
  printf '%s\n' "$HOME/.copilot/skills/caveman" "$(_caveman_claude_dir)/skills/caveman"
}

# _caveman_replace_notes: righe di piano per ciò che verrebbe sostituito (mai cancellato).
_caveman_replace_notes() {
  local dest link
  dest="$(_caveman_skills_dir)/caveman"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "sostituisce $(_caveman_tilde "$dest") se diversa dalla skill (backup in $(_caveman_tilde "$dest").devbar-<data>)"
  fi
  while IFS= read -r link; do
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      echo "sostituisce $(_caveman_tilde "$link") (backup in $(_caveman_tilde "$link").devbar-<data>)"
    fi
  done < <(_caveman_copilot_links)
}

# _caveman_backup <path>: sposta <path> in <path>.devbar-<data> (mai cancellare).
_caveman_backup() {
  local p="$1" b n=1
  b="$p.devbar-$(date +%Y%m%d-%H%M%S)"
  while [ -e "$b" ] || [ -L "$b" ]; do b="$p.devbar-$(date +%Y%m%d-%H%M%S)-$n"; n=$((n + 1)); done
  journal_before "$p" "$b" </dev/null || return 1
  mv "$p" "$b" || return 1
  echo "devbar: $p sostituito, backup in $b" >&2
}

_caveman_setup_copilot() {
  local cache src dest rule f link
  cache="$(_caveman_cache)"
  src="$cache/skills/caveman"
  dest="$(_caveman_skills_dir)/caveman"
  [ -d "$src" ] || { echo "devbar: skill caveman non trovata: $src" >&2; return 1; }
  # registro: skill e link come sono ora (cartelle in tar, link come target)
  # shellcheck disable=SC2046 # un percorso per riga, senza spazi in $HOME attesi
  journal_before "$dest" $(_caveman_copilot_links) </dev/null || return 1
  # Cartella diversa dalla skill: backup, poi copia nuova. Uguale: niente da fare.
  if { [ -e "$dest" ] || [ -L "$dest" ]; } && ! diff -rq "$src" "$dest" >/dev/null 2>&1; then
    _caveman_backup "$dest" || return 1
  fi
  if [ ! -e "$dest" ]; then
    mkdir -p "$dest" || return 1
    cp -R "$src/." "$dest/" || return 1
  fi
  while IFS= read -r link; do
    mkdir -p "$(dirname "$link")" || return 1
    # ln -sfn su una cartella reale creerebbe il link dentro: prima il backup
    if [ -e "$link" ] && [ ! -L "$link" ]; then _caveman_backup "$link" || return 1; fi
    ln -sfn "$dest" "$link" || return 1
  done < <(_caveman_copilot_links)

  rule="$cache/src/rules/caveman-activate.md"
  [ -f "$rule" ] || { echo "devbar: regola di attivazione non trovata: $rule" >&2; return 1; }
  f="$(_caveman_copilot_file)"
  if [ -L "$f" ]; then
    # come Sparkdock (e rtk): un symlink è gestito altrove, non lo tocchiamo
    echo "devbar: $f è un symlink ($(readlink "$f")): non modificato; inserisci le regole caveman a mano" >&2
  else
    _caveman_inject "$f" "$(cat "$rule")" || return 1
    _caveman_strip_block "$f" "<!-- caveman-begin -->" "<!-- caveman-end -->" || return 1
  fi
  # pulizia di blocchi gestiti in file non nostri (solo non-symlink)
  _caveman_strip_block "$HOME/.config/opencode/AGENTS.md" "$_CAVEMAN_MARKER_BEGIN" "$_CAVEMAN_MARKER_END" || return 1
  _caveman_strip_block "$HOME/.github/copilot-instructions.md" "$_CAVEMAN_MARKER_BEGIN" "$_CAVEMAN_MARKER_END" || return 1
}
