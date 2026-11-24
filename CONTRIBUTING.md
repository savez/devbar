# Contribuire a devbar

Grazie per l'interesse a contribuire a **devbar**! È una menu bar personale per macOS, ma
issue e pull request sono benvenute.

Per le **vulnerabilità** non usare le issue pubbliche: vedi [SECURITY.md](SECURITY.md).

## Principi del progetto

Sono le regole non negoziabili: una PR che le viola non viene accettata.

1. **Niente senza conferma.** Ogni azione che scrive o installa mostra prima il piano e
   chiede conferma (`--yes`). Il piano è solo testo: l'app lo mostra, non lo esegue. Non
   esistono azioni "rimuovi" automatiche.
2. **Ogni scrittura nei file di altri programmi passa dal registro.** Config degli harness
   AI, skill, regole, hook e file nei repo si scrivono con gli helper di `lib/common.sh`
   (`devbar_write_file`, `inject_block`, `config_update`) e `lib/journal.sh`, così
   `devbar undo` può annullarle. Mai `cp`, `mv` o `>` diretti su file non tuoi.
3. **Il motore decide, l'app disegna.** Tutta la logica di controllo sta in bash (`lib/`).
   L'app Swift lancia la CLI e mostra il risultato: niente logica di check in Swift.
4. **Il contratto è scritto.** Motore e app si scambiano JSON descritto in `schemas/` e
   verificato dai test. Il motore è la verità: se l'app si aspetta altro, si corregge l'app.
5. **I test non toccano il Mac vero.** Si usano stub e una `HOME` temporanea. Un test non
   chiama mai `brew`, `colima`, `launchctl` o `devbar run …` reali.
6. **Locale e generico.** devbar non ha un server e non invia dati a nessuno. Cosa
   controllare e cosa installare sta nella configurazione, non nel codice: niente
   pacchetti forzati.

## Ambiente di sviluppo

Serve un Mac con macOS 14 o successivo, [Homebrew](https://brew.sh) e i Command Line Tools
(con Swift).

1. Forka il repo e clona il tuo fork:
   ```bash
   git clone https://github.com/<tuo-username>/devbar.git
   cd devbar
   ```
2. Installa gli strumenti di sviluppo:
   ```bash
   brew install just jq bats-core shellcheck check-jsonschema
   ```
3. Comandi utili:
   ```bash
   just test          # test del motore (bats)
   just lint          # shellcheck
   just contract      # rigenera le fixture di contratto e le valida contro schemas/
   just app-test      # test dell'app (swift-testing)
   just app-build     # compila l'app
   just app-snapshots # PNG del pannello e dei Dettagli da fixture, per controllare la grafica
   just build         # bundle firmato ad-hoc in app/.build/devbar.app
   ```
4. Per provare l'app installata: `just install` (e `just uninstall`). Sposta il LaunchAgent
   e `~/.local/bin/devbar` sul tuo Mac: usalo solo se vuoi davvero installarla.

I test dell'app usano swift-testing perché XCTest non c'è nei Command Line Tools; `just
app-test` passa già il percorso del plugin giusto.

## Il contributo più utile: fixture reali

devbar legge l'output di strumenti che non controlla (brew, rtk, tokensave, colima, npm…) e
quei formati cambiano tra le versioni. Per questo i test usano output **registrato dagli
strumenti veri**, in `tests/fixtures/real/<strumento>-<versione>.json`.

**Un controllo sbaglia con una versione nuova di uno strumento?** Lancia
`just record-fixtures` (esegue solo comandi di lettura e anonimizza percorsi e nomi) e apri
una PR con la fixture e la correzione. Un controllo che non riconosce il formato deve
rispondere "formato di <strumento> non riconosciuto (versione X)" con codice `2`, mai con un
numero sbagliato: la fixture reale è ciò che lo prova.

Non committare fixture con nomi di repo privati, percorsi della tua home o token:
`record-fixtures` rifiuta di scriverle, ma controlla comunque.

## Flusso di lavoro

1. **Apri prima una issue** per modifiche grandi (nuove funzioni, refactor, breaking
   change). Per correzioni piccole e ovvie puoi passare direttamente al punto 2.
2. Crea un branch da `main` aggiornato:
   ```bash
   git checkout main && git pull
   git checkout -b feat/<descrizione-breve>
   ```
   Prefissi: `feat/`, `fix/`, `chore/`, `docs/`.
3. Scrivi codice e test. Prima di aprire la PR devono passare `just test`, `just lint`,
   `just contract` e, se tocchi l'app, `just app-test` e `just app-build`.
4. Messaggi di commit in formato
   **[Conventional Commits](https://www.conventionalcommits.org/it/)**:
   - `feat(scope): descrizione`: nuova funzione (versione minor)
   - `fix(scope): descrizione`: correzione (versione patch)
   - `perf: …`, `refactor: …`: versione patch
   - `docs: …`: documentazione
   - `chore: …`, `test: …`, `ci: …`, `build: …`, `style: …`: manutenzione, fuori dal CHANGELOG
   - `feat!: …` o footer `BREAKING CHANGE: …`: versione major

   > 🤖 CHANGELOG e release sono generati da
   > [release-please](https://github.com/googleapis/release-please) a partire dai commit:
   > non modificare `CHANGELOG.md` né `version.txt` a mano.

5. Pubblica il branch sul tuo fork e apri una PR verso `main`, compilando il template.

## Cosa aspettarti nella review

- Il maintainer rivede la PR e può chiedere modifiche (vedi `.github/CODEOWNERS`).
- Se cambia l'output di un comando: schema in `schemas/` e fixture aggiornati (`just
  contract`).
- Se la PR scrive in file di altri programmi: deve passare dal registro e avere un test
  con `HOME` temporanea.
- Dopo il merge su `main`, release-please aggiorna la PR di rilascio. Il merge di quella PR
  crea la release e solo allora la pipeline compila l'app macOS.

## Stile

- **Motore in bash**, compatibile con la bash di sistema di macOS (3.2): niente array
  associativi né funzioni di bash 4+. Passa `shellcheck` (`just lint`). Un solo oggetto
  JSON su stdout per comando; log e diagnostica su stderr. Codici di uscita dei check:
  `0` da fare, `1` a posto, `2` errore, `3` non configurato.
- **App in Swift/SwiftUI**: la logica sta in `DevbarCore` (modelli e view-model, con test),
  le viste in `Devbar` restano sottili. Stato nelle viste in oggetti `@Observable`, non
  con `@State`: la macro non c'è nei Command Line Tools.
- Una nuova area segue il modello `Features/Colima`: modelli, view-model, riga e scheda
  dei Dettagli nella propria cartella, dietro il protocollo `Feature`.
- Testi dell'interfaccia in italiano, con un linguaggio semplice e orientato all'azione.
- Nei test bats non usare `! comando`: non fa fallire il test. Usa
  `run comando; [ "$status" -ne 0 ]`.
- File piccoli, una responsabilità per file.

## Struttura

```text
bin/devbar          dispatcher della CLI
lib/checks/         un file per area di controllo (brew, audit, colima, token)
lib/actions/        azioni dirette (brew, colima, caveman, terminale)
lib/ai/             setup degli strumenti AI per ogni harness
lib/journal.sh      registro delle modifiche e undo
lib/project.sh      Init progetto
schemas/            contratto JSON, uno schema per comando
statusline/         statusline per Claude Code
scripts/            installer, registrazione delle fixture, icona (`make-icon.sh`)
tests/              test bats del motore, con stub e fixture
app/Sources/DevbarCore/   modelli, view-model, runner, store di stato
app/Sources/Devbar/       viste SwiftUI
app/Tests/                test dell'app (swift-testing)
app/Icon/                 icona dell'app (SVG e .icns)
```

## Domande

Apri una issue o una [discussione](https://github.com/savez/devbar/discussions).
