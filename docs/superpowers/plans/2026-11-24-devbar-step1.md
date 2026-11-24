# devbar step 1 (menu bar) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menu bar macOS stile Stats che segnala aggiornamenti brew, vulnerabilità (brew, npm, composer), stato colima, risparmio token e usage Claude, e configura gli strumenti AI per harness e per progetto.

**Architecture:** Motore = CLI bash `devbar` (`bin/devbar` + `lib/`) che stampa JSON su stdout ed esce con codici fissi. UI = app SwiftUI (`app/`) con `MenuBarExtra` stile finestra che lancia la CLI e disegna lo stato; nessuna logica di controllo in Swift. Configurazione in `~/.config/devbar/config.json`.

**Tech Stack:** bash 5 + `jq`, test con `bats-core`, `shellcheck`; Swift 6.4 / SwiftPM, SwiftUI, Swift Charts, XCTest; LaunchAgent.

**Spec:** `docs/superpowers/specs/2026-11-24-devbar-design.md`

## Global Constraints

- Codici di uscita dei check: `0` c'è qualcosa da fare, `1` tutto a posto, `2` errore, `3` non configurato o strumento assente.
- Ogni check stampa **un solo oggetto JSON** su stdout; log e diagnostica su stderr.
- Cache in `~/.cache/devbar/` (override `DEVBAR_CACHE_DIR`); vulnerabilità 24 ore (1440 minuti); `--force` salta la cache.
- Un solo `devbar check all` alla volta (lock in cache dir).
- Config: `~/.config/devbar/config.json` (override `DEVBAR_CONFIG`). Chiavi e default:
  `{"repoRoots":[],"scanDepth":4,"dailyCheckTime":"09:00","harnesses":[],"brewExclude":[],"terminal":"Terminal","launchAtLogin":true}`.
- Scansione repo solo dentro `repoRoots`, fino a `scanDepth`, saltando `node_modules`, `vendor`, `.git`.
- Mai installare, rimuovere o scrivere in un repo senza conferma: le azioni che scrivono richiedono `--yes`; senza, stampano solo il piano. Nessuna azione "rimuovi".
- Nessuna dipendenza dal clone `~/.local/share/sparkdock` a runtime.
- File presi da Sparkdock: intestazione con origine (`github.com/sparkfabrik/sparkdock`, GPLv3) e citazione nel README.
- App: macOS 14.0 minimo, bundle id `it.savez.devbar`, installata in `~/Applications/devbar.app`, LaunchAgent `~/Library/LaunchAgents/it.savez.devbar.plist`.
- Testi della UI in italiano.

## Review Focus

1. **Comandi che stampano testo prima del JSON** (es. `tokensave discover` stampa `Ingested N new turns…`; `brew outdated` stampa `==> Downloading…`; `brew vulns` esce ≠0 quando trova vulnerabilità): il check deve estrarre il JSON ed uscire `2` solo se il JSON manca o è malformato. Test: fixture con preambolo in Task 3 e Task 6.
2. **Cartella in `repoRoots` inesistente o senza permessi:** la scansione la salta con un avviso su stderr, non fallisce. Test in Task 4.
3. **colima installato ma spento / docker non raggiungibile:** il check esce `1` con `running:false`, niente container, nessun errore. Test in Task 5.
4. **Config assente o JSON rotto:** i check usano i default; un config rotto dà un avviso su stderr e i default, l'app mostra "config non valida" nelle impostazioni. Test in Task 1 e Task 12.
5. **Processo CLI che non termina** (rete lenta su `npm audit`, `brew vulns`): l'app lo uccide dopo il timeout e mostra la riga come errore senza bloccare le altre. Test in Task 12.

---

## Struttura dei file

```
bin/devbar                      dispatcher (check | run | detect | repos | version)
lib/common.sh                   config, cache, lock, emit_json, require_tool
lib/checks/brew.sh              brew-outdated, brew-vulns
lib/checks/audit.sh             repos scan, npm-audit, composer-audit
lib/checks/colima.sh            colima
lib/checks/tokens.sh            rtk, tokensave, caveman, claude-usage
lib/detect.sh                   harness e strumenti
lib/actions/brew.sh             brew-upgrade, brew-exclude, cork-*
lib/actions/colima.sh           colima-start/stop/install, container-stop
lib/actions/terminal.sh         open_in_terminal
lib/ai/rtk.sh lib/ai/caveman.sh lib/ai/tokensave.sh lib/ai/statusline.sh lib/ai/claude-usage.sh
lib/project.sh                  project-status, project-apply
statusline/devbar-claude-statusline   copiata da Sparkdock
tests/*.bats  tests/helpers.bash  tests/stubs/<tool>  tests/fixtures/<tool>/*.json
app/Package.swift
app/Sources/DevbarCore/         modelli, CLIRunner, ConfigStore, StatusStore
app/Sources/Devbar/             App, viste
app/Tests/DevbarCoreTests/
app/bundle.sh app/Info.plist app/it.savez.devbar.plist
justfile  README.md
```

**Stub per i test bash:** `tests/stubs/<tool>` è uno script che stampa `tests/fixtures/<tool>/${STUB_<TOOL>_FIXTURE}` ed esce con `${STUB_<TOOL>_RC:-0}`, e registra gli argomenti in `$BATS_TEST_TMPDIR/<tool>.calls`. `tests/helpers.bash` mette `tests/stubs` in testa al `PATH`, imposta `DEVBAR_CONFIG`, `DEVBAR_CACHE_DIR`, `HOME` in `$BATS_TEST_TMPDIR`.

---

### Task 0: Repo GitHub privato

**Files:**
- Create: `.gitignore` (`.build/`, `app/.build/`, `.DS_Store`, `*.swp`)

- [ ] **Step 1:** verifica `gh auth status` → account `savez` attivo; `gh repo view savez/devbar` → non esiste.
- [ ] **Step 2:** crea `.gitignore` e committalo (`chore: gitignore`). Non includere `IDEE.md` se ha modifiche non committate: chiedi all'utente.
- [ ] **Step 3:** `gh repo create savez/devbar --private --source=. --remote=origin --push`.
- [ ] **Step 4:** verifica `gh repo view savez/devbar --json visibility -q .visibility` → `PRIVATE`; `git status -sb` → `main...origin/main`.
- [ ] Dopo ogni task successivo: `git push`.

### Task 1: Scheletro del motore

**Files:**
- Create: `bin/devbar`, `lib/common.sh`, `tests/helpers.bash`, `tests/common.bats`, `justfile`

**Interfaces:**
- Produces (in `lib/common.sh`):
  - `config_get <jq-path>` → stampa il valore (default se config assente/rotta)
  - `cache_fresh <name> <minutes>` → rc 0 se `$DEVBAR_CACHE_DIR/<name>.json` è più giovane
  - `cache_read <name>` / `cache_write <name>` (stdin)
  - `with_lock <cmd…>` → rc 2 con `{"status":"error","error":"busy"}` se lock preso
  - `emit <status> <count> <summary> [items-json]` → stampa `{"status","count","summary","items","checkedAt"}` ed esce con il codice dello status (`action`=0, `ok`=1, `error`=2, `unconfigured`=3)
  - `require_tool <bin>` → se manca chiama `emit unconfigured 0 "<bin> non installato"`
- Produces (dispatcher): `devbar check <name> [--force]`, `devbar run <action> [args…]`, `devbar detect`, `devbar repos`, `devbar version`. Nome sconosciuto → stderr `devbar: check sconosciuto: <name>`, rc 2.

- [ ] **Step 1:** `brew install bats-core shellcheck`. Verifica: `bats --version` stampa `Bats 1.`.
- [ ] **Step 2: test che falliscono** in `tests/common.bats`:
  - `devbar check nope` → rc 2, stderr contiene `check sconosciuto: nope`
  - `config_get .scanDepth` senza config → `4`
  - config `{"scanDepth":2}` → `2`; config `{rotto` → `4` e stderr contiene `config non valida`
  - `emit ok 0 "a posto"` → rc 1, JSON con `.status=="ok"` e `.checkedAt` ISO 8601
  - `cache_write x` poi `cache_fresh x 1440` → rc 0; file con mtime -1441 min → rc 1
  - due `with_lock sleep 1` in parallelo → uno esce 2 con `.error=="busy"`
- [ ] **Step 3:** `bats tests/common.bats` → FAIL.
- [ ] **Step 4:** implementa `bin/devbar` (risolve `DEVBAR_ROOT` dal symlink, `source` di `lib/*.sh`, `set -euo pipefail`) e `lib/common.sh`. `justfile` con target `test` (`bats tests`), `lint` (`shellcheck bin/devbar lib/**/*.sh`).
- [ ] **Step 5:** `just test lint` → PASS, nessun warning.
- [ ] **Step 6:** commit `feat(engine): scheletro CLI devbar con config, cache e lock`.

### Task 2: Check e azioni Homebrew

**Files:**
- Create: `lib/checks/brew.sh` (solo `check_brew_outdated` qui), `lib/actions/brew.sh`, `lib/actions/terminal.sh`, `tests/brew.bats`, `tests/stubs/brew`, `tests/stubs/osascript`, `tests/fixtures/brew/outdated*.json`

**Interfaces:**
- Produces: `devbar check brew-outdated` → items `[{"name","kind":"formula|cask","installed","current"}]`, esclusi `brewExclude` e i `pinned`.
- Produces: `open_in_terminal <cmd>` (usa `config_get .terminal`; `Terminal` → `osascript -e 'tell application "Terminal" to do script …'`; `iTerm`/`Ghostty` analoghi; sconosciuto → Terminal). Il comando è quotato con `printf %q`.
- Produces azioni: `devbar run brew-upgrade [pkg]` (apre nel terminale), `devbar run brew-exclude <pkg>` (aggiunge a `brewExclude`, scrittura atomica), `devbar run cork-open`, `devbar run cork-install --yes`.

- [ ] **Step 1: test che falliscono:** fixture con 2 formule + 1 cask, una in `brewExclude` → rc 0, `.count==2`; fixture vuota → rc 1; stdout di brew con `==> Downloading` prima del JSON → JSON letto lo stesso; brew assente → rc 3; `run brew-upgrade wget` → `osascript.calls` contiene `brew upgrade wget`; `run brew-exclude wget` → config contiene `"wget"` una volta sola anche se lanciato due volte; `run cork-install` senza `--yes` → stampa il comando, non chiama brew.
- [ ] **Step 2:** `bats tests/brew.bats` → FAIL.
- [ ] **Step 3:** implementa. `brew outdated --json=v2`; estrai il JSON partendo dalla prima riga che inizia con `{`.
- [ ] **Step 4:** `just test lint` → PASS.
- [ ] **Step 5:** commit `feat(engine): check brew-outdated e azioni brew/cork`.

### Task 3: Vulnerabilità Homebrew

**Files:**
- Modify: `lib/checks/brew.sh` (aggiunge `check_brew_vulns`)
- Test: `tests/brew-vulns.bats`, `tests/fixtures/brew/vulns-*.json`

**Interfaces:**
- Produces: `devbar check brew-vulns [--force]` → items `[{"formula","id","severity","fixAvailable":bool}]`, `.severe` = numero HIGH+CRITICAL. Cache `brew-vulns`, 1440 minuti.

- [ ] **Step 1: test che falliscono:** fixture con 2 vuln (1 HIGH) → rc 0, `.count==2`, `.severe==1`; fixture `findings` vuoti → rc 1; stub che esce 1 ma stampa JSON valido → letto normalmente; JSON con `findings` non lista → rc 2; seconda chiamata entro 24h → stub non richiamato (`brew.calls` ha una riga); `--force` → richiamato; brew senza sottocomando `vulns` (stub `vulns --help` rc 1) → rc 3.
- [ ] **Step 2:** FAIL. **Step 3:** implementa (`brew vulns --json`, conteggio da `findings[].vulnerabilities` come `scan_brew_vulns` di Sparkdock). **Step 4:** PASS + lint.
- [ ] **Step 5:** commit `feat(engine): check brew-vulns con cache giornaliera`.

### Task 4: Scansione repo e audit npm/composer

**Files:**
- Create: `lib/checks/audit.sh`, `tests/audit.bats`, `tests/stubs/npm`, `tests/stubs/composer`, fixture

**Interfaces:**
- Produces: `devbar repos` → `[{"path","name","npm":bool,"composer":bool,"tokensave":bool}]` (npm = `package-lock.json`, composer = `composer.lock`, tokensave = `.tokensave/`).
- Produces: `devbar check npm-audit [--force]` e `devbar check composer-audit [--force]` → items `[{"repo","critical","high","moderate","low"}]` solo repo con almeno una vuln; cache 1440 min. `npm audit --json` in ogni repo (`.metadata.vulnerabilities`); `composer audit --format=json --locked` (conteggi per `severity` in `.advisories`).

- [ ] **Step 1: test che falliscono:** albero in `$BATS_TEST_TMPDIR` con `a/package-lock.json`, `a/node_modules/x/package-lock.json`, `b/c/composer.lock`, `deep/1/2/3/4/5/package-lock.json` → `repos` trova `a` e `b/c`, non `node_modules` né oltre `scanDepth`; root inesistente → saltata, avviso su stderr, rc 0; `repoRoots` vuoto → `check npm-audit` rc 3 con summary `nessuna cartella repo configurata`; npm con 1 critical in `a` → rc 0, `.count==1`; composer assente → `check composer-audit` rc 3; npm che fallisce in un repo (nessun JSON) → quel repo in items con `"error"`, gli altri proseguono.
- [ ] **Step 2:** FAIL. **Step 3:** implementa (`find` con `-maxdepth` e `-prune`). **Step 4:** PASS + lint.
- [ ] **Step 5:** commit `feat(engine): scansione repo e audit npm/composer`.

### Task 5: colima

**Files:**
- Create: `lib/checks/colima.sh`, `lib/actions/colima.sh`, `tests/colima.bats`, `tests/stubs/colima`, `tests/stubs/docker`, fixture

**Interfaces:**
- Produces: `devbar check colima` → `{"status","profiles":[{"name","status","cpus","memoryBytes","diskBytes"}],"containers":[{"id","name","cpu","mem"}]}`; rc 1 sempre se installato (è informativo), rc 3 se assente. `colima list --json` (una riga JSON per profilo); container da `docker stats --no-stream --format json` solo se un profilo è `Running`.
- Produces azioni: `colima-start [profile]`, `colima-stop [profile]`, `container-stop <id>`, `colima-install --yes` (`brew install colima docker`), `colima-logs <id>` (terminale).

- [ ] **Step 1: test che falliscono:** fixture 1 profilo Running + 2 container → `.profiles[0].cpus==4`, `.containers|length==2`; profilo Stopped → `docker` mai chiamato, `.containers==[]`; docker che fallisce con colima Running → `.containers==[]`, rc 1, avviso stderr; colima assente → rc 3; `run colima-stop default` → `colima.calls` contiene `stop default`; `run colima-install` senza `--yes` → nessuna chiamata a brew.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** PASS + lint.
- [ ] **Step 5:** commit `feat(engine): check e azioni colima`.

### Task 6: Check token (RTK, tokensave, caveman, claude-usage)

**Files:**
- Create: `lib/checks/tokens.sh`, `tests/tokens.bats`, stub `rtk`, `tokensave`, `claude-usage`, fixture

**Interfaces:**
- Produces (tutti rc 1 se presenti, rc 3 se assenti; informativi):
  - `check rtk` → `{"saved","input","pct","commands","daily":[{"date","saved"}]}` da `rtk gain -d -f json` (ultimi 7 giorni di `.daily`).
  - `check tokensave` → `{"saved","calls","usd","missedTurns"}` da `tokensave gain --all --json --range 7d` e `.replaceable_turns` di `tokensave discover --json --since 7d`.
  - `check caveman` → `{"mode","version"}`: `mode` da `~/.config/caveman/config.json` `.defaultMode`; `version` = nome cartella più alta in `~/.claude/plugins/cache/caveman/caveman/`. rc 3 se nessuno dei due esiste.
  - `check claude-usage` → passa i campi di `claude-usage --status --json` (`c_pct`,`c_reset`,`w_pct`,`w_reset`,`stale`,`auth`,`error`) dentro `.usage`. **Prima di implementare** lancia `claude-usage --help` dopo l'installazione del Task 9 e usa il flag reale; se il flag differisce, aggiorna questo Interfaces.
- [ ] **Step 1: test che falliscono:** fixture rtk con 10 giorni → `.daily|length==7`; tokensave discover con riga `Ingested 5 new turns…` prima del JSON → `.missedTurns==33`; caveman con config `{"defaultMode":"full"}` e cartella `4.2.0` → `.mode=="full"`, `.version=="4.2.0"`; ogni strumento assente → rc 3.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** PASS + lint.
- [ ] **Step 5:** commit `feat(engine): check di risparmio token e usage Claude`.

### Task 7: Rilevamento harness e `check all`

**Files:**
- Create: `lib/detect.sh`, `tests/detect.bats`

**Interfaces:**
- Produces: `devbar detect` → `{"harnesses":[{"id","installed":bool,"managed":bool}],"tools":{"brew","colima","npm","composer","rtk","tokensave","claude-usage","cork":bool}}`. Harness supportati e rilevamento: `claude` (bin `claude` o `~/.claude`), `opencode` (bin o `~/.config/opencode`), `copilot` (bin `copilot` o `~/.copilot`), `codex` (bin o `~/.codex`), `cursor` (bin `cursor-agent` o `~/.cursor`), `gemini` (bin o `~/.gemini`). `managed` = presente in `harnesses` della config. `cork` = `/Applications/Cork.app` esiste.
- Produces: `devbar check all [--force]` → `{"<nome>":{"rc":N, …json del check}}` per tutti i check dei Task 2–6 più `harnesses`, eseguito sotto `with_lock`. Un check che fallisce non ferma gli altri.
- Produces: `devbar check harnesses` → rc 0 se c'è un harness installato non in `harnesses` (items = quegli id), altrimenti 1.

- [ ] **Step 1: test che falliscono:** `HOME` con `~/.codex` e stub `claude`, config `harnesses:["claude"]` → `codex` installed e non managed, `check harnesses` rc 0 con items `["codex"]`; `check all` con brew che fallisce → `.["brew-outdated"].rc==2` e gli altri presenti; due `check all` paralleli → il secondo `.error=="busy"`.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** PASS + lint.
- [ ] **Step 5:** commit `feat(engine): rilevamento harness e check all`.

### Task 8: AI setup per RTK e tokensave

**Files:**
- Create: `lib/ai/rtk.sh`, `lib/ai/tokensave.sh`, `tests/ai-rtk-tokensave.bats`

**Interfaces:**
- Produces: `devbar run ai-status <tool>` → `{"tool","installed":bool,"harnesses":[{"id","state":"installed|outdated|missing|unsupported"}]}`.
- Produces: `devbar run ai-install <tool> <harness>… [--yes]` → senza `--yes` stampa i comandi; con `--yes` li esegue e ristampa `ai-status`. Dopo un install riuscito aggiunge l'harness a `harnesses` in config.
- Produces: `devbar run tool-install <rtk|tokensave> --yes` (installa il binario: `brew install rtk-ai/tap/rtk`; tokensave con il metodo documentato nel suo README, da verificare con `tokensave --help`/homepage prima di scrivere).
- Comandi per harness:
  - RTK: `claude` → `rtk init -g --auto-patch`; `opencode` → `rtk init -g --opencode --auto-patch` più la patch plugin OpenCode 2.x (porta `patch_opencode_plugin` da Sparkdock `sjust/scripts/rtk/setup.sh`); `copilot` → istruzioni come `setup_copilot` dello stesso file; `cursor` → `rtk init -g --agent cursor`; altri → `unsupported`. Stato: `rtk init --show`.
  - tokensave: `tokensave install --agent <id>` (id supportati dal suo `--help`); stato da `tokensave doctor`.
- [ ] **Step 1: test che falliscono:** `ai-install rtk claude` senza `--yes` → stdout contiene `rtk init -g --auto-patch`, `rtk.calls` vuoto; con `--yes` → chiamato e config `harnesses` contiene `claude`; harness `gemini` per rtk → `unsupported`; `ai-install tokensave claude opencode --yes` → `tokensave.calls` contiene `install --agent claude --agent opencode`; rtk assente → `ai-status rtk` `.installed==false`.
- [ ] **Step 2:** FAIL. **Step 3:** implementa; le funzioni portate da Sparkdock portano l'intestazione di origine. **Step 4:** PASS + lint.
- [ ] **Step 5:** commit `feat(engine): ai setup per RTK e tokensave`.

### Task 9: AI setup per caveman, statusline e claude-usage

**Files:**
- Create: `lib/ai/caveman.sh`, `lib/ai/statusline.sh`, `lib/ai/claude-usage.sh`, `statusline/devbar-claude-statusline`, `tests/ai-caveman-statusline.bats`

**Interfaces:**
- Consumes: `ai-status` / `ai-install` del Task 8 (stesso formato).
- caveman: porta da Sparkdock `sjust/scripts/caveman/setup.sh` (`ensure_caveman_repo`, `write_default_config`, `setup_claude`, `setup_opencode`, `setup_copilot`), cache in `~/.cache/devbar/caveman` invece di `~/.cache/sparkdock/caveman`. Non toccare `defaultMode` se il config esiste.
- statusline: copia `~/.local/share/sparkdock/config/bin/sparkfabrik-claude-statusline` in `statusline/devbar-claude-statusline` con intestazione di origine. `ai-install statusline claude --yes` imposta `.statusLine = {"type":"command","command":"bash \"<DEVBAR_ROOT>/statusline/devbar-claude-statusline\""}` in `~/.claude/settings.json` con backup `settings.json.devbar-<timestamp>` e scrittura atomica, preservando le altre chiavi. Stato `installed` se `.statusLine.command` punta al file di devbar, `outdated` se punta altrove. Harness diverso da `claude` → `unsupported`. Senza `claude` installato, `ai-status statusline` → rc 3.
- claude-usage: `devbar run tool-install claude-usage --yes` scarica `install.sh` e `checksums.txt` dall'ultima release di `github.com/sparkfabrik/claude-usage` (tag risolto dal redirect di `https://github.com/sparkfabrik/claude-usage/releases/latest`, senza API), verifica sha256, esegue. Checksum diverso → rc 2, niente esecuzione.
- [ ] **Step 1: test che falliscono:** statusline su `settings.json` con altre chiavi → chiavi preservate, backup creato, `.statusLine.command` contiene `devbar-claude-statusline`; `settings.json` assente → creato; `settings.json` non valido → rc 2, file intatto; caveman con config esistente `{"defaultMode":"lite"}` → resta `lite`; claude-usage con checksum sbagliato (stub `curl`) → rc 2, `install.sh` non eseguito.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** PASS + lint; esegui a mano `statusline/devbar-claude-statusline < tests/fixtures/statusline/input.json` → stampa una riga.
- [ ] **Step 5:** commit `feat(engine): ai setup per caveman, statusline e claude-usage`.

### Task 10: Init progetto

**Files:**
- Create: `lib/project.sh`, `tests/project.bats`

**Interfaces:**
- Consumes: `ai-status rtk` (Task 8), `devbar repos` (Task 4).
- Produces: `devbar run project-status <dir>` → `{"path","checks":[{"tool":"rtk|caveman|tokensave","ok":bool,"detail","willWrite":[paths]}]}`:
  - rtk: ok se `ai-status rtk` ha almeno un harness gestito `installed` (hook globale; niente file nel repo).
  - caveman: ok se nel repo esiste la regola sempre attiva che scrive la skill `caveman-init` (stessi file e marcatori; leggi la skill in `~/.claude/plugins/cache/caveman/caveman/*/skills/caveman-init/` prima di implementare e copia elenco file e contenuto).
  - tokensave: ok se `.tokensave/` esiste e `tokensave status` nel repo non segnala indice da aggiornare; `willWrite` = `.tokensave/` e git hook.
- Produces: `devbar run project-apply <dir> [--yes]` → senza `--yes` = `project-status`; con `--yes` applica solo i check non ok (`tokensave init` + `tokensave install --git-hook yes` nel repo; regola caveman), poi ristampa lo stato.
- [ ] **Step 1: test che falliscono:** repo git vuoto → 3 check, caveman e tokensave `ok:false`, `willWrite` non vuoto; `project-apply` senza `--yes` → nessun file creato (`git status --porcelain` vuoto); con `--yes` → `tokensave.calls` contiene `init`, file regola caveman presente; secondo `--yes` → nessuna nuova scrittura; `<dir>` non repo git → rc 2 `non è un repo git`.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** PASS + lint.
- [ ] **Step 5:** commit `feat(engine): init progetto`.

### Task 11: Pacchetto Swift e modelli

**Files:**
- Create: `app/Package.swift`, `app/Sources/DevbarCore/Models.swift`, `app/Sources/DevbarCore/ConfigStore.swift`, `app/Tests/DevbarCoreTests/ModelsTests.swift`, `app/Tests/DevbarCoreTests/Fixtures/*.json`
- Modify: `justfile` (target `app-test`: `cd app && swift test`)

**Interfaces:**
- Produces: `enum CheckState { case action, ok, error, unconfigured }` da rc (`0,1,2,3`); `struct CheckResult: Decodable { state, count, summary, items, checkedAt }`; risultati tipizzati `BrewOutdated`, `BrewVulns`, `AuditResult`, `ColimaStatus`, `RtkGain`, `TokensaveGain`, `CavemanStatus`, `ClaudeUsage`, `DetectResult`, `AIStatus`, `ProjectStatus` — campi = JSON dei Task 2–10.
- Produces: `struct DevbarConfig: Codable` (chiavi e default dei Global Constraints) e `final class ConfigStore { load() -> (DevbarConfig, error: String?); save(_:) throws }` (scrittura atomica, preserva chiavi sconosciute).
- [ ] **Step 1: test che falliscono:** decodifica di un output reale di `devbar check all` salvato in fixture (generalo con `bin/devbar check all > app/Tests/…/all.json`); `ConfigStore` su file assente → default; su JSON rotto → default + `error != nil`; save poi load → uguale e chiave sconosciuta `"x":1` preservata.
- [ ] **Step 2:** `cd app && swift test` → FAIL. **Step 3:** implementa (`platforms: [.macOS("14.0")]`, target `DevbarCore` library + `Devbar` executable + test). **Step 4:** PASS.
- [ ] **Step 5:** commit `feat(app): pacchetto Swift, modelli e config`.

### Task 12: CLIRunner e StatusStore

**Files:**
- Create: `app/Sources/DevbarCore/CLIRunner.swift`, `app/Sources/DevbarCore/StatusStore.swift`, `app/Tests/DevbarCoreTests/StatusStoreTests.swift`

**Interfaces:**
- Produces: `protocol CLIRunning { func run(_ args: [String], timeout: TimeInterval) async -> (rc: Int32, stdout: Data, stderr: String) }`; `CLIRunner` trova `devbar` (env `DEVBAR_BIN`, poi `/opt/homebrew/bin/devbar`, poi `~/.local/bin/devbar`), `PATH` con `/opt/homebrew/bin`; al timeout termina il processo e torna rc 2.
- Produces: `@Observable @MainActor final class StatusStore { results: [String: CheckResult]; isRefreshing; lastRefresh; badge: (level: CheckState, count: Int); func refresh(force: Bool) async; func panelOpened() async; func run(action: [String]) async -> (rc, stdout) }`. `badge.count` = somma di `count` dei check con stato `action`; `level` = `error` se brew-vulns ha `severe>0` o un audit ha `critical/high>0`, altrimenti `action` se almeno uno è action, altrimenti `ok`.
- Eventi (in `StatusStore.startObserving()`): `NSWorkspace.didWakeNotification`, `NWPathMonitor` ritorno a `.satisfied`, timer giornaliero a `dailyCheckTime` (`--force` solo per questo), avvio. `panelOpened()` rilancia solo se `lastRefresh` > 5 minuti fa. Refresh già in corso → ignorato.
- Timeout: 120 s per `check all`, 30 s per le azioni non interattive.
- [ ] **Step 1: test che falliscono** (con `CLIRunning` finto): rc 0 con vulns severe → `badge.level == .error`; runner che non termina entro timeout (finto che dorme) → riga in errore e altre righe aggiornate; `panelOpened()` due volte entro 5 min → runner chiamato una volta; due `refresh` concorrenti → una sola chiamata.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** PASS.
- [ ] **Step 5:** commit `feat(app): runner della CLI e store di stato con eventi`.

### Task 13: Barra e pannello

**Files:**
- Create: `app/Sources/Devbar/DevbarApp.swift`, `app/Sources/Devbar/Panel/*.swift` (una vista per sezione: `BrewSection`, `VulnsSection`, `ColimaSection`, `TokensSection`, `AISetupSection`, `FooterBar`)

**Interfaces:**
- Consumes: `StatusStore` (Task 12), modelli (Task 11).
- `MenuBarExtra(content:label:)` con `.menuBarExtraStyle(.window)`. Etichetta: SF Symbol (`checkmark.shield` verde / `arrow.triangle.2.circlepath` arancio / `exclamationmark.shield` rosso) + numero se `count > 0`.
- Sezioni come nello schema del design; una sezione con stato `unconfigured` mostra solo il pulsante Init (Cork, colima, claude-usage, tokensave, rtk) o niente (composer, npm, statusline senza `claude`). Grafico RTK: `Chart` a barre su `daily` (7 giorni). Claude usage: due `ProgressView` con orario di reset.
- Azioni che scrivono o installano: `confirmationDialog` con il comando mostrato prima di lanciare con `--yes`.
- Pulsante "Dettagli" (vulns, audit): lista espandibile nella sezione; "apri repo" → `devbar run open-terminal <path>` (aggiungi l'azione in `lib/actions/terminal.sh` con test bats).
- [ ] **Step 1:** test bats per `run open-terminal <path>` (osascript chiamato con `cd '<path>'`) → FAIL → implementa → PASS.
- [ ] **Step 2:** implementa le viste. Verifica: `cd app && swift build` senza errori; `DEVBAR_BIN=$PWD/../bin/devbar swift run Devbar` mostra l'icona; con `colima stop` la sezione colima mostra "Avvia"; con un PATH senza `colima` mostra "Init colima".
- [ ] **Step 3:** commit `feat(app): icona nella barra e pannello`.

### Task 14: AI setup, Init progetto e impostazioni nella UI

**Files:**
- Create: `app/Sources/Devbar/AISetup/HarnessPicker.swift`, `app/Sources/Devbar/AISetup/ProjectInitView.swift`, `app/Sources/Devbar/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `ai-status`, `ai-install`, `project-status`, `project-apply`, `repos`, `detect` (Task 7–10), `ConfigStore` (Task 11).
- HarnessPicker: al clic su un pulsante strumento chiama `ai-status <tool>`; se nessun harness è `managed`, mostra la lista degli harness installati con spunte; poi conferma e `ai-install <tool> <ids> --yes`; mostra lo stato aggiornato per harness. Solo "Installa" e "Aggiorna".
- Avviso harness nuovo: se `check harnesses` è `action`, una riga nel pannello "Trovato <id>: gestirlo?" che apre le impostazioni. Non installa nulla da sola.
- ProjectInitView: lista da `repos` + "Scegli cartella…" (`NSOpenPanel`), mostra `project-status` con `willWrite`, pulsante "Applica" → conferma → `project-apply --yes`.
- SettingsView (finestra `Settings` di SwiftUI): cartelle repo (aggiungi con `NSOpenPanel`, rimuovi), profondità (Stepper 1–8), orario giornaliero, harness con spunte (spuntarne uno nuovo lancia `ai-install` per ogni strumento già `installed` su un altro harness, dopo conferma), pacchetti esclusi, terminale (Terminal / iTerm / Ghostty), avvio al login (crea/rimuove il LaunchAgent con `launchctl bootstrap/bootout`), errore "config non valida" se `ConfigStore.load().error != nil`.
- [ ] **Step 1:** implementa. Verifica a mano con `DEVBAR_CONFIG` e `HOME` di prova: init RTK su `claude` mostra i comandi, conferma, stato diventa `installed`; aggiungere una cartella repo e chiudere le impostazioni → `config.json` aggiornato e `devbar repos` la include; Init progetto su un repo di prova crea solo i file elencati.
- [ ] **Step 2:** commit `feat(app): ai setup, init progetto e impostazioni`.

### Task 15: Bundle, installazione e README

**Files:**
- Create: `app/bundle.sh`, `app/Info.plist`, `app/it.savez.devbar.plist`, `README.md`
- Modify: `justfile` (target `build`, `install`, `uninstall`)

**Interfaces:**
- `just build` → `swift build -c release` e `app/bundle.sh` assembla `app/.build/devbar.app` (`LSUIElement=true`, `CFBundleIdentifier=it.savez.devbar`), firma ad-hoc (`codesign --force --sign -`).
- `just install` → copia in `~/Applications/devbar.app`, symlink `~/.local/bin/devbar` → `bin/devbar` del repo, LaunchAgent `~/Library/LaunchAgents/it.savez.devbar.plist` (`RunAtLoad`, `ProcessType Interactive`, `LimitLoadToSessionType Aqua`, come Sparkdock), `launchctl bootstrap gui/$(id -u)`. `just uninstall` fa l'inverso.
- README: cosa fa, `just install`, codici di uscita, chiavi di config, elenco dei comandi `devbar`, sezione "Origine" che cita Sparkdock (statusline, setup caveman e RTK portati da `github.com/sparkfabrik/sparkdock`, GPLv3).
- [ ] **Step 1:** implementa. Verifica: `just install` → `launchctl print gui/$(id -u)/it.savez.devbar` mostra `state = running`; icona visibile; `just uninstall` → plist e app rimossi, processo terminato.
- [ ] **Step 2:** `just test lint app-test` → tutto PASS.
- [ ] **Step 3:** commit `feat: bundle, LaunchAgent e README`.
