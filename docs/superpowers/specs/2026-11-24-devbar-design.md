# devbar: design

Data: 2026-11-24. Sostituisce le parti decise di `IDEE.md`.

## Intento

Una menu bar personale per macOS che tiene il Mac di sviluppo **aggiornato e
protetto** e mostra se gli strumenti AI di risparmio token funzionano. Serve a
**monitorare e lanciare script**, non a inizializzare un Mac da zero.
Riferimento: Sparkdock (`~/Documents/personale/sparkdock`), di cui si
riprende l'architettura (script di controllo bash + app menu bar Swift), non il
catalogo di software da installare.

Stile di interazione: come **Stats**. Nella barra un'icona con poche
informazioni; al clic un pannello con tutto (sezioni, grafici, pulsanti) e una
mini pagina di impostazioni.

## Fasi

1. **Step 1: menu bar** (questo documento, in dettaglio).
2. **Step 2: chezmoi** per l'inizializzazione (stato, `apply`, `update`). Solo
   abbozzato qui.
3. **Step 3: statusline di Claude Code personalizzabile** dalle impostazioni.
   Solo abbozzato qui.

## Obiettivi (step 1)

- Avvisare di aggiornamenti Homebrew e vulnerabilità (formule, npm, composer).
- Mostrare stato e risorse di colima, con avvio e arresto.
- Configurare gli strumenti AI (RTK, caveman, tokensave, statusline) sugli
  harness scelti, e configurare un singolo progetto.
- Riepilogare il risparmio token (RTK, tokensave, caveman) e l'usage di Claude
  Code.

## Non obiettivi

- Interfaccia propria per cercare e installare pacchetti brew: si usa **Cork**
  (`brew install --cask cork`).
- Alias, funzioni, cheat di navi: tolti.
- Installazione di software di base del Mac (il lato "provisioning" di
  Sparkdock).

## Anti-obiettivi

- Installare o rimuovere qualcosa senza conferma esplicita. Mai rimozioni
  automatiche.
- Scrivere file in un repo senza mostrare prima cosa cambia.
- Scansionare tutto il disco: le scansioni restano nelle cartelle configurate.
- Mostrare sezioni per strumenti che non ci sono (rumore).

## Vincoli

- macOS su Apple Silicon. Swift 6.4 presente (Command Line Tools), niente Xcode
  necessario. Go non installato.
- Strumenti presenti oggi: `brew`, `colima`, `node`/`npm`, `rtk`, `tokensave`,
  plugin caveman 4.2.0, harness `claude`, `opencode`, `copilot`. Assenti:
  `composer`, `claude-usage`, `codex`, `gemini`, `cursor`.
- L'utente non vuole scrivere Swift: la logica sta negli script, la UI Swift la
  mantiene l'agente.

## Approcci considerati

| | Come | Pro | Contro |
|---|---|---|---|
| **A. SwiftUI + script bash (scelto)** | `MenuBarExtra` stile finestra, Swift Charts, controlli in bash | è il pannello di Stats, leggero, API native per risveglio/rete/login, Sparkdock come esempio | Swift, che all'utente non piace |
| B. Tauri + script bash | tray Rust + finestra HTML/JS posizionata sotto l'icona | UI web comoda | pannello imitato, stranezze di focus, due linguaggi |
| C. Go systray + pagina localhost | binario Go | — | Go assente, niente pannello, grafici nel browser |
| SwiftBar/xbar | plugin bash | prototipo veloce | solo menu di testo: niente grafici né impostazioni |

Scelta dell'utente: **A**, "seguire come è fatto Sparkdock", "usa Swift se è la
cosa migliore".

## Architettura

Due parti separate, come Sparkdock:

### Motore: CLI `devbar` (bash)

- Un dispatcher `devbar` con sottocomandi: `devbar check <nome> [--force]`,
  `devbar run <azione> [argomenti]`, `devbar detect`.
- **Codici di uscita dei check** (presi da `sparkdock-check-updates`):
  `0` c'è qualcosa da fare, `1` tutto a posto, `2` errore, `3` non configurato
  o strumento assente.
- **Output JSON su stdout** per i dettagli (liste, numeri, serie per i grafici).
  La UI disegna lo stato dal codice di uscita e i dettagli dal JSON.
- **Cache** in `~/.cache/devbar/` per i controlli lenti (vulnerabilità: 24 ore;
  `--force` la salta).
- **Un solo controllo completo alla volta** (lock file).
- Ogni check e azione si può lanciare e testare da terminale senza l'app.

### UI: app Swift

- SwiftPM, `MenuBarExtra` con stile finestra (pannello), Swift Charts.
- Lancia la CLI con timeout, legge codice di uscita e JSON. Nessuna logica di
  controllo in Swift.
- **Eventi, non polling:** avvio, risveglio del Mac, ritorno della rete,
  controllo giornaliero all'orario impostato, apertura del pannello
  (con limite, per non rilanciare tutto a ogni clic), pulsante "Aggiorna".
- Installazione come Sparkdock Manager: `make build` / `make install` in
  `~/Applications/devbar.app`, LaunchAgent per l'avvio al login, firma ad-hoc.
- Le azioni lunghe o interattive (`brew upgrade`, installazioni) si aprono nel
  terminale così l'output è visibile. Il terminale si sceglie in impostazioni;
  predefinito Terminal.app via `osascript`, perché Warp non si comanda in modo
  affidabile da script (scelta dell'agente: l'utente non ha indicato il
  terminale). Le azioni quelle brevi (start/stop colima) girano
  in background con esito nel pannello.

### Configurazione

- `~/.config/devbar/config.json` (JSON perché Swift lo legge senza
  dipendenze; la CLI lo legge con `jq`). Gestibile da chezmoi nello step 2.
- Contenuto: cartelle dei repo, profondità di scansione, orario del controllo
  giornaliero, harness gestiti, pacchetti esclusi dagli avvisi brew.
- Scritto dalla pagina impostazioni dell'app; editabile a mano.

## Barra

Un'icona colorata secondo il problema più grave (verde a posto, arancio
aggiornamenti, rosso vulnerabilità alte/critiche) più il **numero di cose da
fare**, es. `⚠ 4`. (Proposta dell'agente; l'utente non ha scelto altro.)

## Pannello: sezioni

Regola generale: **una sezione compare solo se il suo strumento esiste**.
Se manca, al suo posto c'è un pulsante "Init <strumento>" dove ha senso, oppure
nulla.

```
 ┌──────────────────────────────────────────┐
 │ Homebrew   3 da aggiornare   [Aggiorna]  │
 │            [Apri Cork / Installa Cork]   │
 │ Vulnerabilità                            │
 │   brew      1 alta (oggi 09:00) [Dettagli]│
 │   npm       2 repo con critiche [Dettagli]│
 │   composer  —                            │
 │ colima     ● 4 CPU 8GiB 60GiB 2 cont. [Stop]│
 │ ── Token ──────────────────────────────  │
 │ RTK 179K salvati (18%)  ▁▂▅▇ 7gg         │
 │ tokensave 0 salvati, 2 chiamate (7gg)    │
 │ caveman  full · 4.2.0                    │
 │ Claude usage  5h 42%  settimana 18%      │
 │ ── AI setup ───────────────────────────  │
 │ [RTK] [caveman] [tokensave] [statusline] │
 │ [Init progetto]                          │
 │ ⚙ Impostazioni   ⟳ Aggiorna   Esci       │
 └──────────────────────────────────────────┘
```

### 1. Homebrew

- Check: `brew outdated --json` (formule e cask), esclusi i pacchetti in
  configurazione. Eventi standard.
- Azioni: aggiorna tutto (`brew upgrade`, nel terminale), aggiorna un
  pacchetto, escludi un pacchetto.
- Cork: "Apri Cork" se installato, altrimenti "Installa Cork"
  (`brew install --cask cork`, con conferma).

### 2. Vulnerabilità (una volta al giorno, cache 24h)

- **brew:** `brew vulns`. Elenco pacchetto, gravità, se c'è correzione.
  Azione: aggiorna e ricontrolla. Limite dichiarato nella UI: solo formule.
- **npm:** per ogni repo con `package-lock.json` trovato nelle cartelle
  configurate, `npm audit --json`. Riepilogo per repo per gravità.
- **composer:** stessa cosa con `composer.lock` e `composer audit --format=json`.
  La riga compare solo se `composer` è installato.
- Scansione: solo nelle cartelle configurate, fino alla profondità impostata,
  saltando `node_modules`, `vendor`, `.git`.
- Dettagli: lista per repo e pacchetto, con "apri repo nel terminale".

### 3. colima

- Visibile solo se `colima` è installato; altrimenti "Init colima"
  (`brew install colima docker`, con conferma).
- Stato da `colima list --json`: profili, stato, CPU, RAM, disco.
- Container: `docker ps` e `docker stats --no-stream` (CPU e RAM per
  container), solo se colima è acceso.
- Azioni: avvia/ferma colima (per profilo), ferma un container, apri i log.

### 4. Token

- **RTK:** `rtk gain -f json` (totale) e andamento giornaliero per il grafico.
- **tokensave:** `tokensave gain --all --json --range 7d`; occasioni perse da
  `tokensave discover --json --since 7d`.
- **caveman:** modalità da `~/.config/caveman/config.json` e versione del
  plugin installato. Non esiste una CLI di statistiche: niente numeri di
  risparmio in step 1.
- **Claude usage:** dal binario `claude-usage`
  (github.com/sparkfabrik/claude-usage, lo stesso di Sparkdock): percentuale
  della finestra di 5 ore e settimanale, con orario di reset. Se manca,
  "Init claude-usage".
- Ogni riga compare solo se lo strumento esiste.

### 5. AI setup

**Harness.** `devbar detect` trova gli harness installati (binario o cartella
di configurazione: oggi `claude`, `opencode`, `copilot`).

- Al primo "Init" di uno strumento, devbar mostra gli harness trovati e
  l'utente sceglie quali gestire. La scelta si salva in configurazione.
- In impostazioni c'è la lista degli harness con spunte. Spuntarne uno nuovo
  lancia per quell'harness le configurazioni già attive (RTK, caveman,
  tokensave; statusline se è Claude Code).
- Se compare un harness installato non spuntato, il pannello lo segnala senza
  toccare nulla.

**Strumenti** (ognuno con stato per harness: installato / da aggiornare /
assente; azioni solo "installa" e "aggiorna"):

| Strumento | Visibile se | Comando per harness |
|---|---|---|
| RTK | almeno un harness supportato | `rtk init -g --agent <x>` (OpenCode: `--opencode`) |
| caveman | almeno un harness supportato | script propri di devbar, scritti prendendo spunto da `sjust/scripts/caveman/setup.sh` di Sparkdock |
| tokensave | almeno un harness supportato; se `tokensave` manca, "Init tokensave" lo installa | `tokensave install --agent <x>` |
| statusline | **solo se `claude` è installato** | imposta `statusLine` in `~/.claude/settings.json` sulla statusline di devbar |

**Origine degli script (decisione dell'utente).** devbar contiene i propri
script di installazione per ogni harness e **non dipende dal clone di
Sparkdock** (`~/.local/share/sparkdock`). Gli script di Sparkdock sono solo
spunto. Nello step 2 lo script chezmoi `run_onchange_after_20-ai-agents.sh`
smette di usare Sparkdock e chiama `devbar`, così la fonte di verità è una.

**Statusline (decisione dell'utente).** La statusline di Sparkdock
(`config/bin/sparkfabrik-claude-statusline`, 370 righe) si copia nel repo devbar
e da lì la mantiene l'utente. Il README e l'intestazione del file citano
l'origine Sparkdock. Sparkdock è GPLv3: il file copiato resta GPLv3, quindi se
devbar diventa pubblico deve avere una licenza compatibile (GPLv3).

**Claude usage.** "Init claude-usage" usa lo installer ufficiale della release
GitHub di `sparkfabrik/claude-usage`, verificando `checksums.txt` come fa il
wrapper di Sparkdock.

**Init progetto.** Pulsante che apre l'elenco dei repo trovati nelle cartelle
configurate, più "scegli cartella…". Per il repo scelto:

1. Verifica e mostra lo stato:
   - RTK: hook globale attivo per gli harness scelti.
   - caveman: regola nel repo per gli agenti IDE (come la skill
     `caveman-init`).
   - tokensave: `.tokensave/` presente e indice aggiornato; git hook di sync.
2. Mostra quali file verrebbero creati o modificati nel repo.
3. Applica solo dopo conferma (`tokensave init`, regola caveman, hook).

### 6. Impostazioni

- Cartelle dei repo da monitorare (aggiungi/rimuovi) e profondità.
- Orario del controllo giornaliero.
- Harness gestiti (spunte).
- Pacchetti brew esclusi dagli avvisi.
- Avvio al login.
- Terminale per le azioni lunghe.
- (Step 3) editor della statusline.

## Step 2 e 3 (abbozzo)

- **chezmoi:** sezione con file modificati non salvati (`chezmoi status`),
  commit remoti nuovi, azioni `apply`/`update`, e "Init chezmoi" se manca.
  Include `~/.config/devbar/config.json` tra i file gestiti.
- **statusline:** oggi `settings.json` punta a
  `~/.local/share/sparkdock/config/bin/sparkfabrik-claude-statusline`. Lo step 3
  la sostituisce con una statusline propria i cui elementi si scelgono dalle
  impostazioni. Da progettare a parte.

## Decisioni prese dall'agente (da verificare)

- Configurazione in JSON, non TOML.
- Icona nella barra: colore del problema più grave + numero di cose da fare.
- Terminale predefinito Terminal.app, sceglibile in impostazioni.
- Azioni brevi in background, lunghe nel terminale.
- caveman in step 1 mostra solo modalità e versione (non ha una CLI di
  statistiche).

## Lasciato al costruttore

- Struttura del repo (es. `bin/`, `app/`, `Makefile`), nomi dei sottocomandi.
- Formato preciso del JSON di ogni check.
- Come rilevare "da aggiornare" per ogni strumento AI e harness.
- Versione minima di macOS (quella che `MenuBarExtra` stile finestra e Swift
  Charts richiedono).
- Test: script testabili con fixture (come `SPARKDOCK_CHECK_ROOT`), test unitari
  Swift sul parsing.
