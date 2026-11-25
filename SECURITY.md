# Security Policy

devbar scrive nei file di altri programmi (config degli strumenti AI, hook, regole nei
repo) e lancia comandi sul tuo Mac: un difetto qui può toccare file che non sono suoi. Le
segnalazioni sono benvenute e prese sul serio.

## Versioni supportate

| Versione                          | Supportata |
| --------------------------------- | ---------- |
| Ultima release su `main`          | Sì         |
| Versioni precedenti               | No         |

## Come segnalare una vulnerabilità

Se trovi una vulnerabilità, **non aprire una issue pubblica**.

Usa **GitHub Security Advisories**: la segnalazione resta privata tra te e il maintainer.

<https://github.com/savez/devbar/security/advisories/new>

In alternativa scrivi a [@savez](https://github.com/savez) su GitHub.

### Cosa includere

- Descrizione della vulnerabilità
- Passi per riprodurla (meglio con un PoC)
- Versione di devbar (`devbar version`) e di macOS
- Impatto stimato

### Tempi di risposta

Progetto personale open source, quindi best effort:

- **Presa in carico**: entro 72 ore
- **Correzione o mitigazione**: entro 14 giorni per gravità alta, best effort per le altre

## Modello di sicurezza

I principi sono descritti in [CONTRIBUTING.md](CONTRIBUTING.md#principi-del-progetto):

- **Niente senza conferma.** Le azioni che scrivono o installano mostrano il piano e
  chiedono conferma (`--yes`). Il piano è solo testo: l'app non lo esegue mai.
- **Ogni scrittura è registrata e annullabile.** Le modifiche ai file di altri programmi
  passano da un registro con backup (`devbar journal`, `devbar undo`). Se un file è stato
  cambiato da un altro programma dopo devbar, l'annullamento non lo sovrascrive senza
  `--force`, e la versione dell'altro programma viene conservata.
- **Nessun comando costruito da testo libero.** Gli identificativi (harness, strumenti,
  profili, container) sono validati contro un elenco o un'espressione stretta prima di
  arrivare a un comando; gli argomenti passati al terminale sono quotati.
- **Download verificati.** `tool-install claude-usage` scarica da una release GitHub solo
  con `https`, controlla lo `sha256` dello script e non lo esegue se non coincide.
- **Nessun server, nessuna telemetria.** devbar non invia dati a un server del maintainer.
  I controlli sono comandi locali; alcuni interrogano i servizi dei rispettivi strumenti
  (per esempio `brew vulns` e `npm audit`).
- **Firma ad-hoc, non notarizzata.** L'app non ha un Developer ID. `install.sh` toglie
  l'attributo di quarantena dal bundle installato: scarica lo zip solo dalle release
  ufficiali di questo repo.

## Strumenti attivi

- **Test** del motore e dell'app, in locale (la pipeline non li esegue per risparmiare minuti
  macOS)
- **Dependabot** per gli aggiornamenti delle action della pipeline
- **release-please** per versioni e CHANGELOG

## Divulgazione

Una volta confermato e corretto il problema:

1. pubblico una GitHub Security Advisory con i dettagli (CVE se applicabile);
2. cito chi l'ha segnalato, se lo desidera;
3. la correzione compare nel CHANGELOG con riferimento all'advisory.

## Fuori ambito

- Vulnerabilità degli strumenti che devbar chiama (brew, npm, colima, rtk, tokensave…):
  segnalale ai rispettivi progetti.
- Vulnerabilità del sistema operativo dell'utente.
- L'accesso fisico a un Mac sbloccato.

## Licenza

Rilasciato sotto licenza GPLv3 (vedi [LICENSE](LICENSE)), senza garanzie, "AS IS".
