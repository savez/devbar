# devbar: irrobustimento (contratti, feature, fixture reali, registro modifiche)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** rendere devbar più robusto e manutenibile senza cambiare cosa vede l'utente: contratto JSON scritto e verificato, area colima isolata come modulo, fixture registrate dagli strumenti veri, registro delle modifiche con annullamento.

**Architecture:** il motore bash resta. Ogni comando `devbar` ha uno schema JSON in `schemas/`; i test bats validano l'output, i test Swift decodificano fixture prodotte dal motore stesso. Nell'app, colima diventa una cartella `Features/Colima` (Model, Feature = ViewModel, Row, Details) dietro un protocollo `Feature` minimo: è il pilota, le altre aree seguono dopo approvazione. Le scritture su file di altri programmi passano da un registro con backup e `devbar undo`.

**Tech Stack:** bash + jq + bats, `check-jsonschema` (Homebrew, solo sviluppo), Swift 6.4 / SwiftUI / swift-testing.

**Spec:** `docs/superpowers/specs/2026-11-24-devbar-design.md` più le decisioni dell'utente del 24/11: schemi JSON sì; separazione per area con pilota su colima; fixture reali; registro modifiche. Pagina di analisi: https://claude.ai/artifact/S3tDyjGZ1g3G92pvarmPpo

## Global Constraints

- Nessun cambiamento visibile: stessi testi, stessi pulsanti, stessi screenshot (`just app-snapshots`) salvo dove un task lo dice.
- Mai eseguire sul Mac reale `devbar run …`, `just install`, launchctl, installazioni. Solo comandi di lettura.
- `just test`, `just lint`, `just app-test`, `just app-build` verdi dopo ogni task.
- Niente `@State` (macro assente nelle Command Line Tools): stato in oggetti `@Observable`. Test Swift con swift-testing.
- Commit in italiano stile conventional, push su `feat/step1`.

## Review Focus

1. Uno schema troppo permissivo (tutto opzionale, `additionalProperties` libero ovunque) non protegge nulla: i campi che l'app legge devono essere `required` con tipo esatto.
2. Fixture registrate che contengono dati personali (percorsi della home, nomi di repo privati, token): vanno anonimizzate prima del commit.
3. Il pilota colima non deve lasciare doppioni: il codice colima tolto da `PanelModel`/`PanelActions`/`DetailsView` non resta anche lì.
4. Il registro modifiche non deve mai cancellare il backup prima che il ripristino sia riuscito, e `undo` su un file cambiato nel frattempo da un altro programma deve chiedere conferma, non sovrascrivere.
5. `record-fixtures` deve eseguire solo comandi di lettura.

---

### Task 1: Schemi JSON e test di contratto

**Files:**
- Create: `schemas/` con uno schema (JSON Schema draft 2020-12) per: ogni `check <nome>` (brew-outdated, brew-vulns, npm-audit, composer-audit, colima, rtk, tokensave, caveman, claude-usage, harnesses), `check all`, `detect`, `repos`, `check-timeouts`, `run ai-status`, `run project-status`, il piano senza `--yes` (forma comune), `run caveman-mode`, l'uscita `{tool,terminal:true}` di `tool-install`.
- Create: `tests/contract.bats`; `tests/contract-fixtures.sh` che produce l'output di ogni comando con gli stub esistenti e lo scrive in `app/Tests/DevbarCoreTests/Fixtures/contract/<comando>.json`.
- Create: `app/Tests/DevbarCoreTests/ContractTests.swift`.
- Modify: `justfile` (ricetta `contract` = genera fixture + valida; `test` la include), README (sezione "Contratto").

**Interfaces:**
- Produces: `schemas/<comando>.schema.json`; fixture di contratto sempre rigenerabili con `just contract`.
- Gli schemi descrivono i campi che l'app usa come `required` con tipo esatto; i campi extra sono ammessi solo dove il motore li aggiunge davvero (documentato nello schema con `description`).

- [ ] Step 1: `brew install check-jsonschema` (dipendenza di sviluppo, come bats). Aggiungerla ai requisiti nel README.
- [ ] Step 2: test che falliscono: `tests/contract.bats` valida l'output di ogni comando (prodotto con stub e HOME temporanea) contro il suo schema; un caso negativo per ogni schema (un campo required rimosso → validazione fallisce).
- [ ] Step 3: scrivere gli schemi leggendo `lib/` e `app/Sources/DevbarCore/Models.swift`; dove motore e Swift non coincidono, il motore è la verità e lo si annota nel report.
- [ ] Step 4: `ContractTests.swift`: per ogni fixture di contratto, decodifica con i modelli Swift e verifica che ogni campo che l'app usa sia non-nil (non basta che la decodifica non lanci).
- [ ] Step 5: tutti i suite verdi; commit `feat: schemi JSON e test di contratto tra motore e app`.

### Task 2: Pilota "feature module" su colima

**Files:**
- Create: `app/Sources/DevbarCore/Features/Feature.swift` (protocollo minimo), `app/Sources/DevbarCore/Features/Colima/ColimaModels.swift`, `ColimaFeature.swift`; `app/Sources/Devbar/Features/Colima/ColimaRow.swift`, `ColimaDetails.swift`.
- Modify: togliere colima da `PanelModel`, `PanelActions`, `Readouts`, `Details`, `DetailsView`, `PanelView`, `Models.swift`.
- Test: `app/Tests/DevbarCoreTests/ColimaFeatureTests.swift` (spostare lì i test colima esistenti).

**Interfaces:**
```swift
@MainActor public protocol Feature: AnyObject, Observable {
    var area: Area { get }
    var tone: Tone { get }
    var readout: Readout? { get }
    func update(from all: AllChecks)
}
```
- `ColimaFeature`: `@Observable @MainActor final class`, riceve un `ActionRunning` (il runner esistente) e la conferma comune; espone stato, `toggle()`, `stopContainer(_:)`, `openLogs(_:)`, `installColima()` (passa dalla conferma comune), `busy`.
- La striscia di salute e il pannello prendono tono/numero di colima da `ColimaFeature`, non più da `PanelModel`.

- [ ] Step 1: spostare i test colima in `ColimaFeatureTests` puntando alla nuova API → falliscono.
- [ ] Step 2: implementare il modulo, togliere il codice colima dai file condivisi (nessun doppione).
- [ ] Step 3: `just app-snapshots` prima e dopo: i PNG di pannello e Dettagli/colima devono essere identici (confronto byte o pixel; riportare il risultato).
- [ ] Step 4: suite verdi; commit `refactor(app): colima come modulo a sé (pilota)`.

### Task 3: Fixture registrate dagli strumenti veri

**Files:**
- Create: `scripts/record-fixtures.sh` e ricetta `just record-fixtures`.
- Create: `tests/fixtures/real/<strumento>-<versione>.json` (o `.txt` se l'output ha un preambolo).
- Create: `tests/real-formats.bats`.
- Modify: i check che oggi su formato inatteso danno un messaggio generico.

- [ ] Step 1: lo script esegue solo comandi di lettura (`brew outdated --json=v2`, `brew vulns --json`, `rtk gain -d -f json`, `tokensave gain --all --json --range 7d`, `tokensave discover --json --since 7d`, `colima list --json`, `docker stats --no-stream --format json` se raggiungibile, `claude-usage --status` se installato, `npm audit --json` e `composer audit --format=json --locked` solo su un repo di esempio dentro `tests/fixtures/`), legge la versione di ogni strumento e salva l'output anonimizzando home, nomi utente e percorsi privati.
- [ ] Step 2: `tests/real-formats.bats` fa girare ogni check sulla fixture reale più recente di ogni strumento (tramite stub che stampano la fixture) e valida l'uscita contro lo schema del Task 1.
- [ ] Step 3: quando il formato dello strumento non è quello atteso, il check esce `2` con summary "formato di <strumento> non riconosciuto (versione X)", mai con un numero 0. Test per ogni check.
- [ ] Step 4: registrare le fixture su questo Mac, controllare a mano che non contengano dati personali, commit `test: fixture registrate dagli strumenti veri`.

### Task 4: Registro delle modifiche e annullamento

**Files:**
- Create: `lib/journal.sh`; `tests/journal.bats`.
- Modify: `devbar_write_file` (e ogni scrittura di file non di devbar: `inject_block`, `config_update` solo se il file è di altri, link e copie in `lib/ai/*`, `lib/project.sh`, `lib/actions/caveman.sh`) per registrare prima di scrivere.
- Modify: app: voce "Ultime modifiche" (in Impostazioni o nel pannello sotto AI setup) con "Annulla".

**Interfaces:**
- Registro in `~/.local/state/devbar/journal/<timestamp>-<id>/`: `meta.json` `{id, time, command, files:[{path, existed, sha256Before, sha256After}]}` e la copia dei file com'erano.
- `devbar journal` → elenco JSON delle modifiche (schema nel Task 1 aggiornato).
- `devbar undo [<id>] [--yes]` → senza `--yes` il piano; con `--yes` ripristina. Se lo `sha256` attuale di un file non è più `sha256After` (cambiato da altri), il piano lo dice e serve `--force`.
- Tiene le ultime 50 modifiche.

- [ ] Step 1: test che falliscono: scrittura registrata; undo ripristina byte per byte; file creato da devbar → undo lo rimuove; file cambiato da altri → senza `--force` niente; backup mai cancellato prima del ripristino riuscito.
- [ ] Step 2: implementare; aggiornare schema e fixture di contratto.
- [ ] Step 3: UI con conferma (piano mostrato, poi `--yes`), view-model testato.
- [ ] Step 4: suite verdi; commit `feat: registro delle modifiche e devbar undo`.
