# devbar: task step 1

Dettagli, interfacce e test di ogni task nel piano:
[`docs/superpowers/plans/2026-11-24-devbar-step1.md`](docs/superpowers/plans/2026-11-24-devbar-step1.md).
Design: [`docs/superpowers/specs/2026-11-24-devbar-design.md`](docs/superpowers/specs/2026-11-24-devbar-design.md).

Ogni task: test che fallisce, implementazione, test e lint verdi, commit, `git push`.

## Repo

- [ ] **0. Repo GitHub privato** `savez/devbar`
  - [ ] `.gitignore`
  - [ ] `gh repo create savez/devbar --private --source=. --remote=origin --push`
  - [ ] verifica visibilità `PRIVATE`

## Motore (bash, `bin/devbar` + `lib/`)

- [ ] **1. Scheletro CLI**: dispatcher, config, cache, lock, `emit`, `bats-core` e `shellcheck`
- [ ] **2. Homebrew**: `check brew-outdated`, `run brew-upgrade|brew-exclude|cork-open|cork-install`, apertura nel terminale
- [ ] **3. Vulnerabilità brew**: `check brew-vulns`, cache 24h, `--force`
- [ ] **4. Repo e audit**: `devbar repos`, `check npm-audit`, `check composer-audit`
- [ ] **5. colima**: `check colima`, `run colima-start|colima-stop|container-stop|colima-install|colima-logs`
- [ ] **6. Token**: `check rtk|tokensave|caveman|claude-usage`
- [ ] **7. Harness e aggregato**: `devbar detect`, `check harnesses`, `check all`
- [ ] **8. AI setup RTK e tokensave**: `run ai-status|ai-install|tool-install`
- [ ] **9. AI setup caveman, statusline, claude-usage**: port da Sparkdock, statusline copiata
- [ ] **10. Init progetto**: `run project-status|project-apply`

## App (Swift, `app/`)

- [ ] **11. Pacchetto e modelli**: `DevbarCore`, `ConfigStore`
- [ ] **12. CLIRunner e StatusStore**: timeout, eventi (risveglio, rete, giornaliero, apertura pannello)
- [ ] **13. Barra e pannello**: icona con badge, sezioni, grafico RTK, `run open-terminal`
- [ ] **14. AI setup, Init progetto, impostazioni**: scelta harness, avviso harness nuovo, finestra impostazioni
- [ ] **15. Bundle e installazione**: `make build|install|uninstall`, LaunchAgent, README con origine Sparkdock

## Da verificare prima di implementare

- [ ] Flag JSON reale di `claude-usage` (task 6, dopo installazione al task 9)
- [ ] Metodo di installazione di `tokensave` (task 8)
- [ ] File scritti dalla skill `caveman-init` (task 10)

## Dopo lo step 1

- [ ] Step 2: chezmoi (stato, apply/update, script `run_onchange_after_20-ai-agents.sh` che chiama `devbar`)
- [ ] Step 3: statusline personalizzabile dalle impostazioni
