# TokenEconomizer in devbar e card "Token risparmiati" più chiara

Design breve, 25/11/2026.

## Perché

L'utente usa [TokenEconomizer](https://github.com/microsoft/TokenEconomizer) (plugin per
harness AI, Apache-2.0) e vuole gestirlo da devbar come RTK, caveman e tokensave: vedere se è
attivo e attivarlo sul Mac e sui repo. Nella stessa occasione la card "Token risparmiati" va
resa leggibile: oggi non si capisce a quale strumento appartengono il numero grande, le barre
e le righe 5h / 7 giorni.

## Obiettivi

1. **Vedere se è attivo**: installato (clone presente), plugin installato e abilitato per
   ogni harness, `enabled` vero nella config di `te`, numero di repo seguiti.
2. **Attivarlo sul Mac**: clone come dice il loro README, poi plugin per ogni harness scelto
   in devbar.
3. **Attivarlo su un repo**: da "Init progetto".
4. **Card "Token risparmiati" ridisegnata** come nel mockup (proposta 2, senza stima): una riga
   per strumento con colore, valore e una frase su cosa misura; limiti di Claude in una
   sezione a parte.

## Non obiettivi

- Nessuna stima dei token risparmiati da TokenEconomizer e nessun `te toolprune measure`
  (con Claude Code fa due richieste `claude -p` a pagamento).
- Nessuna gestione di microskills / toolprune / loopguard da devbar (resta `te config`).
- Nessun Dettagli dedicato a TokenEconomizer in questa versione.
- Harness sperimentali (opencode, Cursor, Grok…) esclusi: solo Claude Code, Codex, Copilot.

## Anti-obiettivi

- Un numero nel pannello che non viene da una misura vera.
- Modificare il clone esistente dell'utente o reinstallare un plugin già presente.
- Una qualsiasi azione che parte senza piano e conferma.

## Approcci considerati

1. **Clone + plugin per harness, come il README** (scelto dall'utente). Fonte ufficiale,
   funziona per tutti e tre gli harness.
2. Marketplace diretto da GitHub (`claude plugin marketplace add microsoft/TokenEconomizer`):
   niente clone, ma il README chiede il clone per Codex e Copilot. Scartato.
3. Proposta 1 (solo attività) e proposta 2 con stima via `measure`: l'utente ha scelto la
   proposta 2 e poi tolto la misura; resta la riga con stato e repo seguiti.

## Come funziona

**Motore** (`lib/ai/tokeneconomizer.sh`, stesso schema di `lib/ai/tokensave.sh`):

- **Clone**: si cerca prima un clone esistente, dal marketplace `tokeneconomizer` in
  `~/.claude/plugins/known_marketplaces.json` (`source: directory`, `path`). Se manca, il
  clone va in `~/.local/share/devbar/TokenEconomizer`. `te` = `<clone>/plugin/scripts/te`.
- **Installato**: il clone esiste e contiene `plugin/scripts/te`.
- `tool-install tokeneconomizer`: `git clone https://github.com/microsoft/TokenEconomizer.git
  <cartella>`, con piano e `--yes`. Non tocca un clone già presente.
- **Harness supportati**: `claude`, `codex`, `copilot`.
- **Stato per harness**: plugin `tokeneconomizer@tokeneconomizer` installato (Claude: in
  `~/.claude/plugins/installed_plugins.json`; Codex e Copilot: dall'elenco dei plugin della
  rispettiva CLI, da verificare in fase di piano).
- **Install per harness**: `<cli> plugin marketplace add <clone>` e poi
  `<cli> plugin install tokeneconomizer@tokeneconomizer` (Codex: `codex plugin add`). Il piano
  ricorda i passi manuali del README: fidarsi della cartella e, per Claude Code, lanciare
  `/tokeneconomizer:toolprune refresh-catalog` una volta.
- **Undo**: i file li scrive la CLI dell'harness. Si registrano nel journal solo i percorsi
  noti, come per tokensave; il piano dice cosa non si può annullare.
- **Check `tokeneconomizer`**: installato o no (codice `3` se manca), `enabled` dalla config
  globale (`te config show` o `te status --json`), repo seguiti da `te repos --json`, harness
  con plugin. Codice `0` se il plugin manca su un harness scelto, `1` se tutto a posto.

**Su un repo** ("Init progetto"): nuovo controllo `_proj_check_tokeneconomizer`. Ok se il
plugin è installato per almeno un harness e `enabled` è vero per quel repo. Se è spento,
l'azione è `te config set enabled=on --cwd <repo>`, che scrive
`~/.tokeneconomizer/repos/<chiave>/config.json` (fuori dal repo), registrato nel journal.

**App**:

- Card "Token risparmiati": numero grande = somma di RTK e tokensave con sottotitolo che lo
  dice; righe per RTK (con le barre dei 7 giorni), tokensave, TokenEconomizer (pill
  attivo/spento, valore "N repo", frase "plugin su Claude Code, Codex"), caveman (stato).
- Nuova sezione "Limiti di Claude": "Sessione 5 ore" e "Settimana" con percentuale e data di
  azzeramento.
- AI setup: pulsante "TokenEconomizer" come gli altri strumenti.
- Contratto: schema `schemas/` per il nuovo check, fixture reali con `just record-fixtures`.

## Lasciato a chi costruisce

- Come leggere i plugin installati di Codex e Copilot (comando della CLI o file).
- Colori per strumento nei toni del pannello esistente, chiaro e scuro.
- Testi esatti delle frasi per riga, in linea con gli altri.
