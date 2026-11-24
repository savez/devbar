# devbar

Menu bar personale per macOS: un'icona colorata che dice se c'è qualcosa da sistemare sul Mac di sviluppo (pacchetti Homebrew vecchi o vulnerabili, vulnerabilità npm/composer nei repo, colima, strumenti AI come RTK, tokensave, caveman, consumo di Claude).

Due parti:

- **Motore** (`bin/devbar` + `lib/`): bash, stampa JSON su stdout. Tutta la logica dei check sta qui.
- **App** (`app/`, SwiftUI): lancia la CLI e disegna il risultato. Nessuna logica di check in Swift.

## Requisiti

- macOS 14 o successivo
- [Homebrew](https://brew.sh) e `jq` (`brew install jq`); il motore gira con la bash di sistema di macOS (3.2)
- Command Line Tools con Swift (per compilare l'app)
- Per lo sviluppo: `just`, `bats-core`, `shellcheck`

La statusline per Claude Code (`statusline/devbar-claude-statusline`) richiede bash >= 4.2.

## Installazione

```
just install     # compila, installa ~/Applications/devbar.app, avvia il LaunchAgent
just uninstall   # ferma e rimuove app, symlink e LaunchAgent (la config resta)
```

`just install`:

1. compila in release e assembla `app/.build/devbar.app` (`LSUIElement`, firma ad-hoc);
2. copia il bundle in `~/Applications/devbar.app`;
3. crea il symlink `~/.local/bin/devbar` verso `bin/devbar` di questo repo;
4. scrive `~/Library/LaunchAgents/it.savez.devbar.plist` (`RunAtLoad`, `ProcessType Interactive`, `LimitLoadToSessionType Aqua`) e fa `launchctl bootstrap gui/$(id -u)`. Il plist lo genera l'app stessa (`Devbar --print-launch-agent-plist <eseguibile>`): una sola fonte, la stessa che usa l'opzione "Avvio al login" nelle impostazioni.

**Il repo deve restare dov'è.** Il motore non è dentro il bundle: `~/.local/bin/devbar` è un symlink al repo, e `lib/ai/rtk-run`, `lib/ai/patches/` e `statusline/` vengono letti da lì. Spostare o cancellare il clone rompe l'installazione; dopo uno spostamento, rilanciare `just install`.

L'app ammette una sola istanza (controllo sul bundle id `it.savez.devbar`). All'avvio allinea il plist del LaunchAgent alla chiave `launchAtLogin`.

## Sviluppo

```
just test        # bats (motore)
just lint        # shellcheck
just app-test    # swift-testing (XCTest manca nelle Command Line Tools)
just build       # solo il bundle in app/.build/devbar.app
```

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
| `dailyCheckTime` | `"09:00"` | ora del check giornaliero |
| `harnesses` | `[]` | harness AI gestiti |
| `brewExclude` | `[]` | pacchetti Homebrew da ignorare |
| `terminal` | `"Terminal"` | terminale per "apri": `Terminal`, `iTerm`, `Ghostty` |
| `launchAtLogin` | `true` | avvio al login |

Cache in `~/.cache/devbar/` (override `DEVBAR_CACHE_DIR`): vulnerabilità 24 ore, `--force` salta la cache. Un solo `devbar check all` alla volta.

## Comandi

```
devbar check <nome> [--force]
devbar check all [--force]
devbar run <azione> [args...]
devbar detect
devbar repos
devbar version
```

Check: `brew-outdated`, `brew-vulns`, `npm-audit`, `composer-audit`, `colima`, `rtk`, `tokensave`, `caveman`, `claude-usage`, `harnesses`.

Azioni (`devbar run ...`): `ai-status <tool>`, `ai-install <tool> <id...>`, `tool-install <tool>`, `project-status <dir>`, `project-apply <dir>`, `brew-upgrade [pkg]`, `brew-exclude <pkg>`, `cork-open`, `cork-install`, `colima-start|colima-stop [profilo]`, `colima-install`, `colima-logs <id>`, `container-stop <id>`, `open-terminal <dir>`.

Le azioni che scrivono o installano senza `--yes` stampano solo il piano. Non esiste nessuna azione "rimuovi".

## Origine

- La statusline (`statusline/devbar-claude-statusline`) e il setup di caveman e RTK (`lib/ai/`) sono portati da [Sparkdock](https://github.com/sparkfabrik/sparkdock) (SparkFabrik, GPLv3). I file portati hanno l'intestazione con l'origine. Nessuna dipendenza dal clone Sparkdock a runtime.
- La regola `lib/project/caveman-rule.md` (caveman-init) viene dal plugin [caveman](https://github.com/JuliusBrussee/caveman) (Apache-2.0).

Nota licenza: devbar include codice derivato da Sparkdock (GPLv3). Se devbar diventa pubblico deve essere distribuito con una licenza compatibile con GPLv3.
