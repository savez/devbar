# devbar: idee per una menu bar personale

Stato: **bozza da rivedere insieme**. Niente è deciso, nemmeno il nome.

## Obiettivo

Una menu bar per macOS che tiene d'occhio il Mac di sviluppo e permette di
intervenire con un clic: aggiornamenti e vulnerabilità di Homebrew, chezmoi,
Docker su colima, strumenti AI (caveman, RTK, statusline), comandi e alias.

## Principi

- **Generica.** Nessuna scelta imposta: cosa controllare e cosa installare sta
  in un file di configurazione, non nel codice. Niente pacchetti forzati, niente
  rimozioni automatiche (la lezione di Sparkdock).
- **Presa da Sparkdock come idea, non come codice.**
  - Ogni controllo è un comando con un **codice di uscita** fisso:
    `0` c'è qualcosa da fare, `1` tutto a posto, `3` non configurato,
    altro = errore. La UI disegna ogni riga solo da quel codice.
  - **A eventi, non a polling:** avvio, risveglio del Mac, ritorno della rete,
    una volta al giorno, aggiornamento manuale.
  - **Cache** per i controlli lenti (es. vulnerabilità: 24 ore, `--force`
    per saltarla).
  - **Un solo controllo completo alla volta.**
- **Non Swift.** Logica in script o in un piccolo binario, interfaccia
  sostituibile (vedi "Architettura").
- **Nel backup chezmoi:** la configurazione della menu bar vive in chezmoi
  come tutto il resto.

## Funzioni

### 1. Aggiornamenti Homebrew

- Avviso con il numero di formule e cask da aggiornare (`brew outdated`).
- Azioni: aggiorna tutto (`brew upgrade`), aggiorna un pacchetto, escludi
  un pacchetto dagli avvisi.

### 2. Vulnerabilità

- `brew vulns` con cache giornaliera; icona colorata se ce ne sono di gravità
  alta o critica.
- Elenco: pacchetto, gravità, se esiste una correzione (`--fix-available`).
- Azione: "aggiorna e ricontrolla" (`brew upgrade <formula> && brew vulns`).
- Limite da mostrare: controlla solo le formule, non cask, npm, pip e uv.

### 3. Cerca e installa da Homebrew

- Campo di ricerca su formule e cask (`brew search`, `brew info --json`).
- Scheda: descrizione, versione, homepage, se è già installato.
- Azione: installa. Dopo l'installazione, il Brewfile si aggiorna come oggi
  (l'hook `brew` dello `.zshrc`, o un comando dedicato).

### 4. Comandi e alias, in stile navi

- Elenco ricercabile di alias e funzioni dello `.zshrc` e dei cheat di navi
  (`~/.local/share/navi/cheats`), con descrizione.
- Azione: copia il comando, oppure aprilo in un terminale (Ghostty) già
  compilato.
- Le descrizioni si prendono dai commenti sopra l'alias, come fa navi.

### 5. Dashboard Docker / colima

- Stato di colima: acceso o spento, CPU, RAM e disco assegnati alla VM
  (`colima status`, `colima list`).
- Container attivi (`docker ps`) con CPU e RAM di ciascuno (`docker stats
  --no-stream`).
- Azioni: avvia o ferma colima, ferma un container, apri i log.

### 6. Strumenti AI

Installare, aggiornare e verificare, con la configurazione di oggi:

- **caveman**: modalità `full` per Claude Code, OpenCode e Copilot.
- **RTK**: hook per Claude Code, istruzioni per Copilot, plugin OpenCode 2.x.
- **statusline** di Claude Code.

Oggi lo fa lo script `run_onchange_after_20-ai-agents.sh` in chezmoi, che
usa gli script di Sparkdock clonati in `~/.local/share/sparkdock`. La menu bar
mostrerebbe lo stato di ognuno e offrirebbe "installa" e "aggiorna".

### 7. chezmoi

- Avviso se ci sono file modificati e non salvati (`chezmoi status`).
- Avviso se il repo remoto ha commit nuovi.
- Azioni: `chezmoi apply`, `chezmoi update`, salva un file (`chezmoi add`).

### 8. Altre idee (da valutare)

- Aggiornamenti di Claude Code e Codex.
- Aggiornamento del clone di Sparkdock (`git pull`).
- Stato della batteria (cicli, capacità).
- Spazio su disco e pulizia (`brew cleanup`, `docker system prune`).
- HTTP proxy `.loc`, se un giorno lo installi.
- Segreti in chiaro nei file gestiti da chezmoi (es. password in un cheat).

## Architettura: opzioni

| Opzione | Come | Pro | Contro |
|---|---|---|---|
| **A. SwiftBar o xbar** | plugin in bash: lo script stampa il menu | prototipo in poche ore, zero compilazione | ricerca, dashboard e liste lunghe sono scomode (il menu è solo testo) |
| **B. Go + systray** | un binario Go con l'icona nella barra e una piccola dashboard web locale (`localhost`) | un solo eseguibile, UI ricca nel browser, stesso linguaggio della TUI di Sparkdock | da scrivere e compilare; Go oggi non è installato |
| **C. Tauri** | app con UI web (HTML/JS) e un core piccolo | finestra vera, ricerca e dashboard comode | più pesante da impostare, Rust per il core |

Idea comune a tutte: separare il **motore** dalla **UI**.

- Motore: una CLI (`devbar check <nome>`, `devbar run <azione>`) che legge la
  configurazione ed esegue i controlli con il protocollo dei codici di uscita.
- UI: qualunque cosa sopra il motore. Si può partire da SwiftBar e passare a
  Go o Tauri senza riscrivere i controlli.

Proposta da discutere: **motore in bash o Go, prima UI con SwiftBar**, poi
B o C quando servono la ricerca e la dashboard.

## Configurazione (esempio)

```toml
[[check]]
name = "Homebrew"
check = "devbar-checks brew-outdated"   # 0 = aggiornamenti, 1 = a posto
action = "brew upgrade"
events = ["launch", "wake", "network", "daily"]

[[check]]
name = "Vulnerabilità"
check = "devbar-checks brew-vulns --severity high"
cache = "24h"

[[check]]
name = "chezmoi"
check = "devbar-checks chezmoi-status"
action = "chezmoi apply"
```

## Approfondimento da fare: caveman e risparmio di token

Domande aperte:

- Come è configurato oggi: `~/.config/caveman/config.json` ha
  `defaultMode: "full"`, e il plugin `caveman@caveman` 4.2.0 lo attiva a ogni
  sessione con un hook `SessionStart`. Cosa cambia tra le modalità?
- Sta facendo risparmiare davvero? Da misurare con `/caveman-stats` e
  confrontare con sessioni senza caveman.
- Come si sovrappone allo stile di output **Concise** (anche lui accorcia le
  risposte) e a RTK (che accorcia l'output dei comandi, non le risposte)?
- RTK: quanto risparmia, con `rtk gain` e `rtk gain --history`.
- Cosa personalizzare: modalità per progetto, esclusioni, disattivazione per
  certi agenti.

## Decisioni da prendere insieme

1. Nome del progetto.
2. Architettura: A, B o C, e in che ordine.
3. Linguaggio del motore: bash o Go.
4. Dove vive la configurazione (proposta: `~/.config/devbar/config.toml`, in
   chezmoi).
5. Quali funzioni nella prima versione (proposta: 1, 2, 5 e 7).
6. Se la menu bar sostituisce lo script `run_onchange_after_20-ai-agents.sh`
   o lo richiama.
