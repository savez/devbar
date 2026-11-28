# Advisory recenti (smzstudio.it) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un controllo `advisories` nel motore che legge il feed di smzstudio.it/advisories e lo mostra nel pannello (categoria Sicurezza) e in Dettagli con ricerca.

**Architecture:** Come gli altri controlli: `lib/checks/advisories.sh` scarica `https://smzstudio.it/advisories/index.xml`, lo trasforma in JSON con `emit`, cache 6 ore. L'app decodifica il JSON (`Advisories` in `Models.swift`), aggiunge una riga al pannello e una nuova area Dettagli `.advisories`. Nessuna logica di controllo nell'app.

**Tech Stack:** bash 3.2 + `curl`, `xmllint` (o `xsltproc`), `jq`; Swift 6 / SwiftUI, swift-testing; bats e `check-jsonschema`.

**Spec:** `docs/superpowers/specs/2026-11-28-advisories-design.md`

## Global Constraints

- Nessuna dipendenza nuova: solo strumenti già in macOS più `jq`.
- Un solo oggetto JSON su stdout, diagnostica su stderr; rc `0` c'è da fare, `1` a posto, `2` errore, `3` non configurato.
- Cache in `devbar_cache_dir`, `--force` la salta. Un solo GET verso smzstudio.it, nessun dato dell'utente inviato.
- Finestra `advisoriesDays` (default 7); cache 6 ore; `count` = advisory `critical`/`high` più alert tra le recenti.
- Testi dell'interfaccia in italiano. Pochi test: `just test` (bats) e `just app-test`, `just app-build` a fine lavoro.
- Licenza e stile: commenti in italiano come nel resto del motore.

## Review Focus

- Feed non raggiungibile con cache presente: usa la cache, avviso su stderr, rc come se i dati fossero freschi. Test in Task 1.
- Feed non raggiungibile senza cache, o XML rotto: `rc 2` con `status` `error`, mai `ok`. Test in Task 1.
- `advisoriesDays` non numerico, 0 o negativo: torna a 7. Test in Task 1.
- Voce con `title` che non rispetta il formato `[SEVERITY score] pacchetto — titolo`: non rompe il controllo; `severity` `UNKNOWN`, `package` vuoto, il titolo resta intero. Test in Task 1.
- `pubDate` non leggibile: la voce è scartata, non fa fallire il controllo. Test in Task 1.
- Config con `advisoriesDays` salvata dall'app: `ConfigStore` non deve cancellare la chiave. Test in Task 3.

---

### Task 1: Controllo `advisories` nel motore

**Files:**
- Create: `lib/checks/advisories.sh`, `tests/advisories.bats`, `tests/fixtures/advisories/feed.xml`, `schemas/advisories.schema.json`
- Modify: `lib/common.sh` (nuova funzione `advisories_days`), `lib/detect.sh` (`DEVBAR_ALL_CHECKS` e `check_timeout_secs`, timeout 60), `schemas/all.schema.json`, `tests/contract.bats` e `tests/contract-fixtures.sh` se elencano i check
- Test: `tests/advisories.bats`

**Interfaces:**
- Produces: `check_advisories [--force]` (chiamato da `devbar check advisories`); `advisories_days` in `lib/common.sh`, stampa un intero 1..90.
- Produces (JSON): busta standard di `emit` più `items` di oggetti
  `{id: string, severity: "CRITICAL"|"HIGH"|"MEDIUM"|"LOW"|"UNKNOWN"|"ALERT", score: number|null, package: string, ecosystem: string, title: string, published: string (ISO 8601 UTC), url: string, source: string}`.
  `ecosystem` è la prima `category` che non è una gravità né `alert`; per gli alert è `"alert"`. `source` è il testo dopo "fonte:" nella `description`, altrimenti `""`.
- Consumes: `cache_fresh`, `cache_read`, `cache_write`, `emit`, `config_get` di `lib/common.sh`.

- [ ] **Step 1: Fixture e test che falliscono**

`tests/fixtures/advisories/feed.xml`: RSS 2.0 con cinque `item`: (a) `[CRITICAL 9.1] vendor/pkg — Titolo` recente, categorie `composer` e `critical`, `description` con "fonte: GitHub Advisory DB"; (b) `[MEDIUM 5.3] ...` recente; (c) `[HIGH 7.5] ...` con `pubDate` di 30 giorni prima; (d) `[ALERT CSIRT Italia] Vulnerabilità in prodotti X` recente, categoria `alert`; (e) titolo senza formato e `pubDate` valida, recente. Le date sono relative: il test genera il file sostituendo i segnaposto `@DAYS_AGO_n@` con date RFC 822 calcolate con `date -u -v-<n>d`.
`tests/advisories.bats` (stub di `curl` con `make_stub curl`, `STUB_CURL_FIXTURE`, come `tests/brew-vulns.bats`; lo stub deve stampare il feed generato):
  - `advisories: voci recenti, count e rc` → `status` 0; `count` = 2 (a e d); `items` ha 4 voci (a, b, d, e); contiene (a) con `severity` `CRITICAL`, `score` 9.1, `package` `vendor/pkg`, `ecosystem` `composer`, `source` `GitHub Advisory DB`; non contiene (c).
  - `advisories: nessuna voce grave recente -> rc 1`.
  - `advisories: voce senza formato -> UNKNOWN`: (e) ha `severity` `UNKNOWN`, `package` `""`.
  - `advisories: pubDate illeggibile -> voce scartata`.
  - `advisories: advisoriesDays non valido torna a 7` (config con `"advisoriesDays": 0`, e `"x"`).
  - `advisories: rete assente con cache -> usa la cache` (prima chiamata ok, poi `STUB_CURL_RC=6`, `--force` non usato: cache fresca; secondo caso con cache vecchia di 7 ore tramite `touch -t`: usa la cache e stderr contiene "cache").
  - `advisories: rete assente senza cache -> rc 2` e `status` `error`.
  - `advisories: XML rotto -> rc 2`.
  - `advisories: output valido per lo schema` (`schema_ok advisories "$output"`).

- [ ] **Step 2: Eseguire i test**

Run: `bats tests/advisories.bats` — Expected: FAIL (check sconosciuto).

- [ ] **Step 3: Implementare `check_advisories` in `lib/checks/advisories.sh` e `advisories_days` in `lib/common.sh`**

Scaricare con `curl -fsS --max-time 30`; se la cache `advisories` (il JSON già convertito, non l'XML) è più giovane di 360 minuti e non c'è `--force`, saltare il download. Convertire l'XML con `xmllint`/`xsltproc` e `jq` (la scelta è di chi implementa; vale `Global Constraints`). Regole: titolo `\[(CRITICAL|HIGH|MEDIUM|LOW|UNKNOWN) ?([0-9.]+)?\] pacchetto — titolo` oppure `[ALERT ...] titolo`; `id` = primo `CVE-…` o `GHSA-…` nella `description`, altrimenti il `guid`; `published` da `pubDate` con `date -u -j -f "%a, %d %b %Y %H:%M:%S %z"` (voce scartata se fallisce); filtro: `published` ≥ ora − `advisoriesDays` giorni. Scrivere nella cache le voci complete (non filtrate), filtrare a ogni esecuzione. `count` = voci `CRITICAL`, `HIGH`, `ALERT` tra le recenti; `summary` "N advisory gravi negli ultimi D giorni" (singolare "1 advisory grave negli ultimi D giorni"), oppure "Nessuna advisory grave negli ultimi D giorni"; `emit action` se `count > 0`, altrimenti `emit ok 0`. `items` contiene tutte le recenti, ordinate dalla più recente. Errore di rete o XML non valido: con cache → avviso su stderr che dice che si usa la cache; senza → `emit error 0 "feed delle advisory non raggiungibile"`.

- [ ] **Step 4: Registrare il check**

Aggiungere `advisories` a `DEVBAR_ALL_CHECKS` e a `check_timeout_secs` (60). Scrivere `schemas/advisories.schema.json` sul modello di `brew-vulns.schema.json` (busta `checkEnvelope`, `items` con i campi sopra, `additionalProperties: false`) e aggiungere `advisories` a `all.schema.json`. Rigenerare le fixture con `just contract`.

- [ ] **Step 5: Verificare**

Run: `bats tests && just lint` — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib schemas tests
git commit -m "feat(engine): check advisories dal feed di smzstudio.it"
```

### Task 2: Modello e store nell'app

**Files:**
- Modify: `app/Sources/DevbarCore/Models.swift`, `app/Sources/DevbarCore/StatusStore.swift` (`checkTimeouts`), `app/Sources/DevbarCore/Readouts.swift` (`Area`), `app/Sources/DevbarCore/PanelModel.swift`
- Test: `app/Tests/DevbarCoreTests/ContractTests.swift`, `ModelsTests.swift`, `StatusStoreTests.swift`, `PanelModelTests.swift`

**Interfaces:**
- Consumes: JSON del Task 1 (fixture rigenerate in `Fixtures/contract`).
- Produces: `public struct AdvisoryItem: Decodable, Equatable, Sendable, Identifiable { id, severity, score: Double?, package, ecosystem, title, published, url, source: String }`; `public struct Advisories: Decodable { result: CheckResult; items: [AdvisoryItem] }` (stesso stile di `BrewVulns`).
- Produces: `Area.advisories` (titolo "Advisory"), aggiunta a `Area.detailsAreas` dopo `.vulns`; `PanelModel.advisoryItems: [AdvisoryItem]`, `PanelModel.advisoryState: SectionKind`, `PanelModel.advisorySummary: String`, `PanelModel.advisoryError: String?`.

- [ ] **Step 1: Test che falliscono**

Test di contratto in `ContractTests.swift`: `advisories` compare nell'elenco dei check, decodifica con `Advisories` e `expectKeys(["id","severity","package","ecosystem","title","published","url","source"], …)` sul primo item. `StatusStoreTests`: `checkTimeouts["advisories"] == 60` e il test che confronta con `devbar check-timeouts` continua a passare. `PanelModelTests`: con fixture ricca `advisoryState == .shown` e `advisoryItems.count > 0`; con riga `unconfigured` o assente `advisoryState == .hidden`; con riga `error` `advisoryError` è il `summary`.

- [ ] **Step 2: Eseguire**

Run: `just app-test` — Expected: FAIL (simboli mancanti).

- [ ] **Step 3: Implementare** i tipi e le proprietà sopra. `AllChecks.typed(Advisories.self, "advisories")` come per `BrewVulns`; `advisoryState` da `SectionKind.of`. La chiave `"advisories"` va anche nei test che elencano le chiavi di `check all` (`ModelsTests`, `FinalReviewTests`). `advisories` non è informativo: contribuisce al badge come le altre vulnerabilità.

- [ ] **Step 4: Verificare**

Run: `just app-test` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app
git commit -m "feat(app): modello e store per le advisory"
```

### Task 3: Pannello, Dettagli con ricerca e configurazione

**Files:**
- Modify: `app/Sources/Devbar/Panel/PanelView.swift`, `app/Sources/Devbar/Details/DetailsView.swift`, `app/Sources/DevbarCore/Details.swift`, `app/Sources/DevbarCore/PanelModel.swift` (tono dell'area), `app/Sources/DevbarCore/ConfigStore.swift` solo se serve per non perdere `advisoriesDays`
- Test: `app/Tests/DevbarCoreTests/PanelModelTests.swift`, `ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `PanelModel.advisoryItems/advisoryState/advisorySummary`, `Area.advisories`, `Tone.severity(_:)`, `PanelModel.severityLabel(_:)` (esistenti).
- Produces: `public struct AdvisoryDetailRow: Equatable, Sendable, Identifiable { id, severity (etichetta italiana), severityRank: Int, score: String, package, ecosystem, title, published: String (data breve), url: URL?, tone: Tone }`; `PanelModel.advisoryDetailRows(search: String) -> [AdvisoryDetailRow]` (filtro senza distinzione tra maiuscole su pacchetto, id e titolo; ordine dalla più recente; la gravità `ALERT` ha etichetta "Alert CERT" e rank 5); `PanelModel.tone(of: .advisories)`.

- [ ] **Step 1: Test che falliscono**

`PanelModelTests`: `advisoryDetailRows(search: "")` mantiene l'ordine per data decrescente; `search: "VENDOR"` trova `vendor/pkg`; `search: "cve-2026"` trova per id; `search: "zzz"` dà `[]`; la voce `ALERT` ha `severity == "Alert CERT"`; `url` non valido dà `nil`. `ConfigStoreTests`: una config con `"advisoriesDays": 3` caricata e salvata mantiene la chiave.

- [ ] **Step 2: Eseguire** `just app-test` — Expected: FAIL.

- [ ] **Step 3: Implementare** `advisoryDetailRows(search:)` e `tone(of:)` per `.advisories` (rischio se ci sono `CRITICAL`/`HIGH`/`ALERT` recenti, azione se solo `MEDIUM`/`LOW`, ok altrimenti).

- [ ] **Step 4: Vista del pannello.** Riga `AdvisoriesRow` nella sezione Sicurezza, sotto `VulnsRow`, nello stile di `VulnsRow` (`ReadoutRow`, `onDetails: { open(.advisories) }`), visibile solo con `advisoryState == .shown`; sottotitolo `advisorySummary`.

- [ ] **Step 5: Vista Dettagli.** `AdvisoriesDetails(model:actions:)` aggiunta allo `switch` di `DetailsView`: `Table` con colonne Gravità (pallino di `tone`), Punteggio, Pacchetto, Ecosistema, Titolo, Data; campo di ricerca (`.searchable` o `TextField` sopra la tabella, testo in `PanelActions` come `advisorySearch`, stile di `vulnFilter`); doppio clic o pulsante sulla riga apre `url` con `NSWorkspace.shared.open`. Con `advisoryItems` vuoto: `EmptyArea(title: "Advisory", message: model.advisoryError ?? "Nessuna advisory recente.")`. `Footnote`: "Fonte: smzstudio.it/advisories, aggiornato ogni 6 ore."

- [ ] **Step 6: Verificare**

Run: `just app-test && just app-build` — Expected: PASS. Controllare a occhio con `just app-snapshots` che pannello e Dettagli si disegnino (aggiungere le advisory alla fixture `all-rich.json` se serve).

- [ ] **Step 7: Commit**

```bash
git add app
git commit -m "feat(app): riga Advisory nel pannello e tabella con ricerca in Dettagli"
```

### Task 4: Documentazione

**Files:**
- Modify: `docs/RIFERIMENTO.md` (elenco check, chiave `advisoriesDays`, cache 6 ore), `README.md` (riga nella tabella "Cosa fa"; frase sulla rete in "Sicurezza prima di tutto": il controllo advisories scarica un feed pubblico da smzstudio.it senza inviare dati)

- [ ] **Step 1:** Aggiornare i due file. Nessun test.
- [ ] **Step 2:** `just test && just app-test && just app-build` — Expected: PASS.
- [ ] **Step 3: Commit**

```bash
git add docs README.md
git commit -m "docs: controllo advisories"
```
