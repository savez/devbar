# Riferimento

Dettagli per chi usa devbar da terminale o vuole capirne il funzionamento. Per iniziare basta il [README](../README.md).

## Codici di uscita dei check

| Codice | Significato |
|---|---|
| `0` | c'è qualcosa da fare |
| `1` | tutto a posto |
| `2` | errore |
| `3` | non configurato o strumento assente |

Ogni check stampa un solo oggetto JSON su stdout (`status`, `count`, `summary`, `items`, `checkedAt`, ...); log e diagnostica vanno su stderr. `devbar check all` esce sempre `1` e stampa un oggetto con un campo per check (ognuno con `rc`).

## Configurazione

`~/.config/devbar/config.json` (override con `DEVBAR_CONFIG`). Assente o rotta: si usano i default (la rotta dà un avviso su stderr e "config non valida" nelle impostazioni).

| Chiave | Default | Significato |
|---|---|---|
| `repoRoots` | `[]` | cartelle in cui cercare repo (solo lì dentro) |
| `scanDepth` | `4` | profondità massima della scansione (salta `node_modules`, `vendor`, `.git`) |
| `dailyCheckTime` | `"09:00"` | ora in cui la scansione delle vulnerabilità viene forzata, solo con `vulnCheckEvery` = `"1d"` |
| `vulnCheckEvery` | `"1d"` | ogni quanto rifare la scansione delle vulnerabilità: `"12h"`, `"1d"`, `"1w"` |
| `brewCheckHours` | `6` | ogni quante ore rifare `brew update` (1, 3, 6, 12, 24); `brew outdated` gira a ogni controllo |
| `harnesses` | `[]` | harness AI gestiti |
| `brewExclude` | `[]` | pacchetti Homebrew da ignorare |
| `terminal` | `"Terminal"` | terminale per "apri": `Terminal`, `iTerm`, `Ghostty` |
| `launchAtLogin` | `true` | avvio al login |

Cache in `~/.cache/devbar/` (override `DEVBAR_CACHE_DIR`): le vulnerabilità (`brew vulns`, `npm audit`, `composer audit`) durano quanto dice `vulnCheckEvery`, `brew update` si rifà ogni `brewCheckHours` ore; `--force` salta la cache. I valori non validi tornano al default. Un solo `devbar check all` alla volta.

## Comandi

```
devbar check <nome> [--force]
devbar check all [--force]
devbar run <azione> [args...]
devbar detect
devbar repos
devbar journal [--limit N]
devbar undo [<id>] [--yes] [--force]
devbar version
```

Check: `brew-outdated`, `brew-vulns`, `npm-audit`, `composer-audit`, `colima`, `rtk`, `tokensave`, `tokeneconomizer`, `caveman`, `claude-usage`, `harnesses`.

Azioni (`devbar run ...`): `ai-status <tool>`, `ai-install <tool> <id...>`, `tool-install <tool>`, `project-status <dir>`, `project-apply <dir>`, `brew-upgrade [pkg]`, `brew-exclude <pkg>`, `cork-open`, `cork-install`, `colima-start|colima-stop [profilo]`, `colima-install`, `colima-logs <id>`, `container-stop <id>`, `open-terminal <dir>`.

Le azioni che scrivono o installano senza `--yes` stampano solo il piano. Non esiste nessuna azione "rimuovi".

## Registro delle modifiche e undo

Ogni `devbar run …` che scrive in file di altri programmi (config degli harness, skill, regole, hook, file di un repo) crea una voce in `~/.local/state/devbar/journal/<data>-<id>/` (override `DEVBAR_STATE_DIR`): `meta.json` con i file toccati (hash prima/dopo) e in `files/` la copia di ognuno com'era prima. Config e cache di devbar non vengono registrate. Si tengono le ultime **50** voci; le più vecchie vengono cancellate con i loro backup.

- `devbar journal [--limit N]`: le voci, dalla più recente (in app: Impostazioni, "Ultime modifiche").
- `devbar undo [<id>]`: il piano per annullare la voce (senza id la più recente non annullata). Con `--yes` ripristina i file e toglie quelli creati da devbar.
- Se un file è stato cambiato da un altro programma dopo devbar, il piano lo segnala (`needsForce`) e `--yes` non tocca nulla. Con `--force --yes` si ripristina comunque: la versione dell'altro programma non viene cancellata, resta nella voce in `<voce>/kept/<percorso assoluto>` (mai accanto all'originale) e sparisce quando la voce esce dalla rotazione.

Cosa non si può annullare da devbar:

- `~/.claude.json`: lo scrive `tokensave install` per Claude Code, ma Claude Code lo riscrive a ogni sessione e un undo riporterebbe indietro anche il suo stato. Il piano di `ai-install tokensave claude` lo dice.
- i file scritti da installer esterni (`tokensave install`, `rtk init`, …) fuori dai percorsi noti a devbar: si registrano solo quelli noti (per tokensave il piano dice quali).
- le installazioni Homebrew (`brew upgrade`, `tool-install`, `colima-install`, …).
