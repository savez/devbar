# TokenEconomizer, card token e intervalli dei controlli: piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** TokenEconomizer gestito da devbar (stato attivo, installazione per harness, attivazione per repo), card "Token risparmiati" con una riga per strumento e "Limiti di Claude" a parte, intervalli configurabili per vulnerabilità e Homebrew.

**Architecture:** Motore bash: nuovo `lib/ai/tokeneconomizer.sh` sull'interfaccia di `lib/ai/ai.sh`, nuovo check `tokeneconomizer`, nuovo controllo in Init progetto, cache delle vulnerabilità e `brew update` guidati da due chiavi di config. App SwiftUI: modelli in `DevbarCore` (con test), viste sottili in `Devbar`.

**Tech Stack:** bash 3.2 + jq, bats, shellcheck, check-jsonschema; Swift 6 / SwiftUI, swift-testing.

**Spec:** `docs/superpowers/specs/2026-11-25-tokeneconomizer-design.md`

## Global Constraints

- Motore compatibile con bash 3.2 (niente array associativi); `just lint` verde.
- Un solo oggetto JSON su stdout per comando; check: rc `0` da fare, `1` a posto, `2` errore, `3` non configurato.
- Ogni azione che scrive o installa: senza `--yes` stampa solo il piano (`plan.schema.json`).
- I test non chiamano mai strumenti veri: stub in `tests/stubs`, HOME temporanea (`setup_env`). Nessun agente lancia `devbar run …` reali, `just install` o `launchctl`.
- Harness TokenEconomizer: solo `claude`, `codex`, `copilot`.
- URL clone: `https://github.com/microsoft/TokenEconomizer.git`; cartella predefinita `~/.local/share/devbar/TokenEconomizer` (override `DEVBAR_TE_DIR`); id plugin `tokeneconomizer@tokeneconomizer`.
- Config nuove: `vulnCheckEvery` ∈ `"12h"|"1d"|"1w"` (default `"1d"`), `brewCheckHours` ∈ `1|3|6|12|24` (default `6`). Valori non validi = default.
- Minuti di cache vulnerabilità: `12h`=720, `1d`=1440, `1w`=10080.
- Nessuna stima di token per TokenEconomizer; nessun `te toolprune measure`.
- Testi UI in italiano, linguaggio semplice. Stato nelle viste con `@Observable`, mai `@State`.
- Pochi test a fine lavoro (preferenza utente): dopo l'ultimo task bastano `just test`, `just lint`, `just contract`, `just app-test`, `just app-build`.

## Review Focus

1. **Homebrew aggiornato a mano dal terminale**: la lista "da aggiornare" deve sparire subito, non dopo 6 ore. Per questo solo `brew update` (rete) è sotto intervallo; `brew outdated` gira a ogni controllo. Test in Task 4.
2. **`brew update` senza rete o che fallisce**: il check prosegue con l'indice locale, nessun errore. Test in Task 4.
3. **Clone di TokenEconomizer già presente** (marketplace locale dell'utente): `tool-install` non clona di nuovo e non tocca la cartella; l'install per harness usa quel percorso. Test in Task 1.
4. **Harness la cui CLI manca** (es. `codex` non installato): stato `missing`, install che fallisce con messaggio chiaro, nessun crash del check. Test in Task 1 e Task 2.
5. **Config con valori strani** (`vulnCheckEvery: "2d"`, `brewCheckHours: 5`, stringa): default, nessun errore. Test in Task 4 (motore) e Task 5 (app).

---

### Task 1: Setup AI di TokenEconomizer (motore)

**Files:**
- Create: `lib/ai/tokeneconomizer.sh`
- Create: `tests/ai-tokeneconomizer.bats`
- Create: `tests/fixtures/tokeneconomizer/` (output stub: `claude-plugins.json`, `known_marketplaces.json`, `copilot-plugins.txt`, `codex-plugins.txt`)
- Modify: `tests/helpers.bash` solo se serve un helper per creare il clone finto

**Interfaces:**
- Produces (interfaccia di `lib/ai/ai.sh`): `ai_tokeneconomizer_supports <h>`, `ai_tokeneconomizer_installed`, `ai_tokeneconomizer_state <h>` (stampa `installed|missing`), `ai_tokeneconomizer_install_cmds <h>...`, `ai_tokeneconomizer_install <h>...`, `ai_tokeneconomizer_tool_install_cmd`, `ai_tokeneconomizer_tool_install`.
- Produces (usati da Task 2 e 3): `te_clone_dir` (stampa il percorso del clone, rc 1 se nessuno), `te_bin` (stampa `<clone>/plugin/scripts/te`, rc 1 se assente).

- [ ] **Step 1: Test che falliscono** in `tests/ai-tokeneconomizer.bats`:
  - `te_clone_dir: legge il marketplace locale` — `known_marketplaces.json` con `{"tokeneconomizer":{"source":{"source":"directory","path":"<tmp>/te-clone"}}}` e `<tmp>/te-clone/plugin/scripts/te` eseguibile → stampa `<tmp>/te-clone`.
  - `te_clone_dir: ripiego su DEVBAR_TE_DIR` — nessun marketplace, clone in `$DEVBAR_TE_DIR` → stampa quello; nessuno dei due → rc 1.
  - `ai-status tokeneconomizer: harness non supportati` — `opencode`, `cursor`, `gemini` → `unsupported`.
  - `ai-status: claude installed` — stub `claude plugin list --json` con `[{"id":"tokeneconomizer@tokeneconomizer","enabled":true}]` → `installed`; con `enabled:false` o assente → `missing`.
  - `ai-status: CLI mancante` — `codex` non nel PATH → `codex` `missing`, rc 0.
  - `tool-install senza --yes`: piano con `git clone https://github.com/microsoft/TokenEconomizer.git <dir>`; nessuna chiamata a `git` registrata.
  - `tool-install con clone già presente`: piano dice che il clone c'è già; con `--yes` nessuna chiamata a `git`.
  - `ai-install tokeneconomizer claude --yes`: `claude.calls` contiene `plugin marketplace add <clone>` e poi `plugin install tokeneconomizer@tokeneconomizer`; per `codex` il secondo comando è `plugin add tokeneconomizer@tokeneconomizer`.
  - Piano di `ai-install`: contiene la riga "non si può annullare da devbar" e il passo manuale `/tokeneconomizer:toolprune refresh-catalog` per claude.

- [ ] **Step 2: Lancia** `bats tests/ai-tokeneconomizer.bats` → FAIL (`tool sconosciuto: tokeneconomizer`).

- [ ] **Step 3: Implementa `lib/ai/tokeneconomizer.sh`**.
  - `te_clone_dir`: prima `jq -r '.tokeneconomizer.source | select(.source=="directory") | .path'` su `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/known_marketplaces.json`, poi `${DEVBAR_TE_DIR:-$HOME/.local/share/devbar/TokenEconomizer}`; vale solo se `plugin/scripts/te` è eseguibile.
  - Stato: claude da `claude plugin list --json` (voce con `id` uguale e `enabled` vero); copilot e codex dal testo di `<cli> plugin list` (riga che contiene `tokeneconomizer`). Verificare i flag esatti con `copilot plugin --help` e `codex plugin --help` prima di scrivere; se `--json` c'è, usarlo.
  - Install: per ogni harness `<cli> plugin marketplace add "<clone>"` poi install (claude/copilot `plugin install`, codex `plugin add`); stdout dei comandi su stderr; nessun `journal_before` (la CLI dell'harness scrive i suoi file).
  - `tool_install`: `git clone --depth 1 <url> <dir>` solo se `te_clone_dir` fallisce; crea la cartella padre.

- [ ] **Step 4: Lancia** `bats tests/ai-tokeneconomizer.bats && just lint` → PASS.

- [ ] **Step 5: Commit** `feat(ai): setup di TokenEconomizer per claude, codex e copilot`.

### Task 2: Check `tokeneconomizer` e contratto

**Files:**
- Modify: `lib/checks/tokens.sh` (nuova `check_tokeneconomizer`)
- Modify: `lib/detect.sh` (`DEVBAR_ALL_CHECKS` aggiunge `tokeneconomizer` dopo `tokensave`)
- Create: `schemas/tokeneconomizer.schema.json`; Modify: `schemas/all.schema.json`
- Modify: `tests/tokens.bats`, `tests/contract-fixtures.sh`, fixture in `app/Tests/DevbarCoreTests/Fixtures/contract/`
- Modify: `app/Sources/DevbarCore/StatusStore.swift` (`informative` e `checkTimeouts` con `"tokeneconomizer": 60`)
- Modify: `app/Sources/DevbarCore/Models.swift` (struct `TokenEconomizerStatus`), `app/Tests/DevbarCoreTests/ContractTests.swift`

**Interfaces:**
- Consumes: `te_clone_dir`, `ai_tokeneconomizer_state` (Task 1); harness scelti da `config_get .harnesses`.
- Produces: output `{status, count:0, summary, items:[], checkedAt, active: Bool}`; rc 3 se non installato. Swift: `public struct TokenEconomizerStatus: Decodable, Equatable, Sendable { public let active: Bool }`.

- [ ] **Step 1: Test che falliscono** in `tests/tokens.bats`:
  - `tokeneconomizer: non installato -> rc 3`.
  - `tokeneconomizer: attivo` — clone finto, `harnesses:["claude"]`, plugin claude installato, `~/.tokeneconomizer/config.json` assente → rc 1, `.active == true`, `summary == "TokenEconomizer attivo"`.
  - `tokeneconomizer: spento da config` — `{"enabled":false}` nel config globale → `.active == false`, `summary == "TokenEconomizer spento"`.
  - `tokeneconomizer: plugin su nessun harness scelto` → `.active == false`, `summary == "TokenEconomizer non installato negli harness scelti"`.
  - Test Swift in `ContractTests`: decodifica la fixture e legge `active`.

- [ ] **Step 2: Lancia** `bats tests/tokens.bats` → FAIL.

- [ ] **Step 3: Implementa `check_tokeneconomizer`** (sempre `status: ok`, rc 1, informativo; `enabled` letto con jq da `~/.tokeneconomizer/config.json`, assente o rotto = vero). Schema come `tokensave.schema.json` con `active` boolean richiesto per ok. `just contract` per rigenerare le fixture.

- [ ] **Step 4: Lancia** `bats tests/tokens.bats tests/contract.bats && just app-test` → PASS (il test che confronta `checkTimeouts` con `devbar check-timeouts` incluso).

- [ ] **Step 5: Commit** `feat(check): stato di TokenEconomizer`.

### Task 3: TokenEconomizer in Init progetto

**Files:**
- Modify: `lib/project.sh` (`_proj_check_tokeneconomizer`, `_proj_status_json`, `action_project_apply`)
- Modify: `schemas/project-status.schema.json` se l'enum dei tool è chiuso
- Modify: `tests/project.bats`
- Modify: `app/Sources/DevbarCore/ProjectInitModel.swift` solo se l'elenco dei tool è fisso

**Interfaces:**
- Consumes: `te_bin` (Task 1).
- Produces: voce `{tool:"tokeneconomizer", ok, detail, willWrite}` in `checks`.

- [ ] **Step 1: Test che falliscono** in `tests/project.bats`:
  - Non installato → `ok:false`, `detail` "TokenEconomizer non installato (usa AI setup)", `willWrite: []`; `project-apply --yes` non chiama `te`.
  - Installato, stub `te config show --cwd <root>` → `{"enabled":true}` → `ok:true`, `detail` "attivo su questo repo".
  - `{"enabled":false}` → `ok:false`, `detail` "spento su questo repo", `willWrite` = percorso config del repo (da `te status --json --cwd <root>`: `dirname` di `.state` + `/config.json`); `project-apply --yes` chiama `te config set enabled=on --cwd <root>` dopo `journal_before` su quel percorso.

- [ ] **Step 2: Lancia** `bats tests/project.bats` → FAIL.

- [ ] **Step 3: Implementa** seguendo il modello di `_proj_check_tokensave`; un TokenEconomizer non installato non blocca gli altri strumenti in `project-apply`.

- [ ] **Step 4: Lancia** `bats tests/project.bats && just contract` → PASS.

- [ ] **Step 5: Commit** `feat(project): attiva TokenEconomizer su un repo`.

### Task 4: Intervalli nel motore

**Files:**
- Modify: `lib/common.sh` (`DEVBAR_DEFAULT_CONFIG` con `"vulnCheckEvery":"1d","brewCheckHours":6`; funzioni `vuln_cache_minutes`, `brew_update_minutes`)
- Modify: `lib/checks/brew.sh` (`check_brew_outdated [--force]`, `check_brew_vulns`), `lib/checks/audit.sh` (i due `1440`)
- Modify: `lib/detect.sh` (`check_timeout_secs`: `brew-outdated` usa `DEVBAR_CHECK_TIMEOUT_AUDIT`)
- Modify: `app/Sources/DevbarCore/StatusStore.swift` (`checkTimeouts["brew-outdated"] = 300`)
- Modify: `tests/brew.bats`, `tests/brew-vulns.bats`, `tests/audit.bats`, `tests/common.bats`

**Interfaces:**
- Produces: `vuln_cache_minutes` (stampa 720|1440|10080), `brew_update_minutes` (stampa ore×60, default 360). Stamp file `$(devbar_cache_dir)/brew-update.stamp` (mtime = ultimo `brew update` riuscito o tentato).

- [ ] **Step 1: Test che falliscono:**
  - `common.bats`: `vuln_cache_minutes` con `12h`→720, `1w`→10080, assente/`"2d"`/`5`→1440; `brew_update_minutes` con `3`→180, assente/`5`/`"x"`→360.
  - `brew.bats`: stamp assente → `brew.calls` contiene `update` prima di `outdated --json=v2`; stamp recente → nessun `update`, `outdated` sì; `--force` → `update` anche con stamp recente; `STUB_BREW_UPDATE_RC=1` → check rc normale e lista corretta.
  - `brew-vulns.bats`: con `vulnCheckEvery:"12h"` una cache di 13 ore viene rifatta, una di 11 ore no.

- [ ] **Step 2: Lancia** `bats tests/common.bats tests/brew.bats tests/brew-vulns.bats tests/audit.bats` → FAIL.

- [ ] **Step 3: Implementa.** `brew update` con `HOMEBREW_NO_INSTALL_CLEANUP=1`, stdout/stderr scartati, errore ignorato; lo stamp si tocca a ogni tentativo (niente retry continui senza rete). `brew outdated` resta senza cache.

- [ ] **Step 4: Lancia** gli stessi bats, `bats tests/contract.bats` e `just lint` → PASS.

- [ ] **Step 5: Commit** `feat(check): intervalli configurabili per vulnerabilità e brew update`.

### Task 5: Impostazioni "Controlli automatici" e pianificazione nell'app

**Files:**
- Modify: `app/Sources/DevbarCore/ConfigStore.swift` (`vulnCheckEvery: String = "1d"`, `brewCheckHours: Int = 6`, CodingKeys, decode tollerante)
- Modify: `app/Sources/DevbarCore/SettingsModel.swift`
- Modify: `app/Sources/DevbarCore/StatusStore.swift` (`scheduleDaily` → `scheduleChecks`)
- Modify: `app/Sources/Devbar/Settings/SettingsView.swift`
- Modify: test in `app/Tests/DevbarCoreTests/` (ConfigStore, SettingsModel, StatusStore)

**Interfaces:**
- Produces: `SettingsModel.vulnOptions: [(id: String, title: String)]` = `[("12h","Ogni 12 ore"),("1d","Ogni giorno"),("1w","Ogni settimana")]`; `SettingsModel.brewOptions: [(hours: Int, title: String)]` = `[(1,"Ogni ora"),(3,"Ogni 3 ore"),(6,"Ogni 6 ore"),(12,"Ogni 12 ore"),(24,"Ogni giorno")]`; `setVulnEvery(_ id: String)`, `setBrewHours(_ h: Int)` (valori fuori elenco ignorati); `showsDailyTime: Bool` (vero solo per `"1d"`).
- `StatusStore`: tick ogni 3600 s con `refresh(force: false)`; forzatura all'orario `dailyCheckTime` solo se `vulnCheckEvery == "1d"` (stessa `nextDailyFire`). Con `12h` e `1w` decide la durata della cache del motore.

- [ ] **Step 1: Test che falliscono:** decode con `vulnCheckEvery:"2d"` e `brewCheckHours:"x"` → default; `setVulnEvery("1w")` salva, `setVulnEvery("3d")` non salva; `setBrewHours(5)` non salva; `showsDailyTime` falso per `12h` e `1w`; il config scritto conserva le chiavi sconosciute come oggi.

- [ ] **Step 2: Lancia** `just app-test` → FAIL.

- [ ] **Step 3: Implementa.** La sezione "Controllo giornaliero" diventa "Controlli automatici": Picker "Vulnerabilità", DatePicker "Orario" solo se `showsDailyTime`, Picker "Homebrew".

- [ ] **Step 4: Lancia** `just app-test && just app-build` → PASS.

- [ ] **Step 5: Commit** `feat(app): intervalli dei controlli automatici nelle impostazioni`.

### Task 6: Card "Token risparmiati", "Limiti di Claude" e AI setup

**Files:**
- Modify: `app/Sources/DevbarCore/PanelModel.swift` (righe per strumento), `app/Sources/DevbarCore/Readouts.swift` (`tokensReadout`)
- Modify: `app/Sources/Devbar/Panel/PanelView.swift` (`TokensRow`, nuova `ClaudeLimitsRow`), `app/Sources/Devbar/Snapshots.swift` se serve per la nuova sezione
- Modify: `app/Sources/DevbarCore/AISetupModel.swift` (`tools` aggiunge `"tokeneconomizer"`, `binaryInstallable` lo include), `PanelModel` `display` aggiunge `"TokenEconomizer"`
- Modify: test in `app/Tests/DevbarCoreTests/` (PanelModel, Readouts, AISetupModel)

**Interfaces:**
- Consumes: `TokenEconomizerStatus` (Task 2).
- Produces: `public struct TokenToolRow: Equatable, Sendable { id: String; title: String; value: String?; detail: String; active: Bool?; daily: [DailySaving] }` e `PanelModel.tokenRows: [TokenToolRow]` in ordine RTK, tokensave, TokenEconomizer, caveman (solo strumenti con riga presente e non `unconfigured`); `PanelModel.tokenTotal: Int?` = somma di `rtkSaved` e `tokensave.saved` presenti.

- [ ] **Step 1: Test che falliscono** (con le fixture di contratto):
  - `tokenRows` RTK: `value == "194K"` (dalla fixture), `detail == "output dei comandi ridotto del 18%"`, `daily.count <= 7`.
  - tokensave: `value == "0"`, `detail == "53 volte l'agente ha letto file invece di usare tokensave"` (numero da `missedTurns`).
  - TokenEconomizer attivo: `value == nil`, `active == true`, `detail == "attivo"`; spento: `active == false`, `detail` = `summary` del check. Non installato: nessuna riga.
  - caveman: `active` dal check, `value == nil`, `detail == "risposte più corte, nessun conteggio disponibile"`.
  - `tokensReadout`: valore = `Fmt.tokens(tokenTotal)`, sottotitolo "somma di RTK e tokensave"; senza nessuno dei due niente numero.
  - `AISetupModel.tools` contiene `tokeneconomizer`.

- [ ] **Step 2: Lancia** `just app-test` → FAIL.

- [ ] **Step 3: Implementa** le viste come nel mockup (https://claude.ai/artifact/UdngBnKCVJw2KJVWsnEUwT, proposta 2 senza stima): quadratino colorato per strumento, nome, valore a destra, riga di dettaglio sotto; barre RTK dentro la riga RTK. `ClaudeLimitsRow` con "Sessione 5 ore" e "Settimana", percentuale e "si azzera …" sotto. Il pulsante "Init" resta per gli strumenti `initOnly`.

- [ ] **Step 4: Lancia** `just app-test && just app-build && just app-snapshots`; guarda i PNG del pannello chiaro e scuro → nessun testo tagliato.

- [ ] **Step 5: Commit** `feat(app): card token con una riga per strumento e limiti di Claude a parte`.

### Task 7: Documentazione e fixture reali

**Files:**
- Modify: `docs/RIFERIMENTO.md` (chiavi `vulnCheckEvery`, `brewCheckHours`; check `tokeneconomizer`; cache: "vulnerabilità secondo `vulnCheckEvery`, `brew update` secondo `brewCheckHours`")
- Modify: `README.md` (riga "Strumenti AI" con TokenEconomizer; Primi passi con "Controlli automatici"), `docs/assets/panel-*.png` da `just app-snapshots`
- Modify: `scripts/record-fixtures.sh` (sola lettura: `te config show`, `claude plugin list --json`)

- [ ] **Step 1:** aggiorna i documenti.
- [ ] **Step 2:** `just record-fixtures` (solo comandi di lettura) e controlla che le fixture nuove non abbiano percorsi personali.
- [ ] **Step 3: Verifica finale** `just test && just lint && just contract && just app-test && just app-build` → tutto verde.
- [ ] **Step 4: Commit** `docs: TokenEconomizer e controlli automatici`.
